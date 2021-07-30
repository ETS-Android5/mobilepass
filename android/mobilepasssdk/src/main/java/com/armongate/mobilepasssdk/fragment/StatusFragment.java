package com.armongate.mobilepasssdk.fragment;

import android.content.Context;
import android.os.Bundle;
import android.os.Handler;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.TextView;

import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;
import androidx.fragment.app.FragmentActivity;

import com.armongate.mobilepasssdk.R;
import com.armongate.mobilepasssdk.activity.PassFlowActivity;
import com.armongate.mobilepasssdk.constant.NeedPermissionType;
import com.armongate.mobilepasssdk.delegate.BluetoothManagerDelegate;
import com.armongate.mobilepasssdk.manager.BluetoothManager;
import com.armongate.mobilepasssdk.manager.ConfigurationManager;
import com.armongate.mobilepasssdk.manager.DelegateManager;
import com.armongate.mobilepasssdk.manager.LogManager;
import com.armongate.mobilepasssdk.model.BLEScanConfiguration;
import com.armongate.mobilepasssdk.model.DeviceCapability;
import com.armongate.mobilepasssdk.model.DeviceConnectionStatus;
import com.armongate.mobilepasssdk.model.WaitingStatusUpdate;
import com.armongate.mobilepasssdk.model.request.RequestAccess;
import com.armongate.mobilepasssdk.model.response.ResponseAccessPointItemDeviceInfo;
import com.armongate.mobilepasssdk.service.AccessPointService;
import com.armongate.mobilepasssdk.service.BaseService;
import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;

import java.lang.reflect.Type;
import java.util.List;

public class StatusFragment extends Fragment implements BluetoothManagerDelegate {
    private String  mActionType;
    private String  mAccessPointId;
    private int     mDeviceNumber;
    private int     mRelayNumber;
    private int     mDirection;
    private String  mNextAction;
    private View    mCurrentView;
    private List<ResponseAccessPointItemDeviceInfo> mDevices;

    private Handler mTimerHandler;

    private FragmentActivity    mActivity;
    private WaitingStatusUpdate mWaitingUpdate = null;

    private DeviceConnectionStatus.ConnectionState mLastConnectionState;
    private boolean mLastBluetoothState = BluetoothManager.getInstance().getCurrentState().enabled;

    @Override
    public View onCreateView(LayoutInflater inflater, ViewGroup container,
                             Bundle savedInstanceState) {
        Gson gson = new Gson();

        String devicesJson = getArguments() != null ? getArguments().getString("devices") : "";
        Type typeDeviceList = new TypeToken<List<ResponseAccessPointItemDeviceInfo>>(){}.getType();

        mDevices            = gson.fromJson(devicesJson, typeDeviceList);
        mActionType         = getArguments() != null ? getArguments().getString("type") : "";
        mAccessPointId      = getArguments() != null ? getArguments().getString("accessPointId") : "";
        mDeviceNumber       = getArguments() != null ? getArguments().getInt("deviceNumber") : 0;
        mRelayNumber        = getArguments() != null ? getArguments().getInt("relayNumber") : 0;
        mDirection          = getArguments() != null ? getArguments().getInt("direction") : 0;
        mNextAction         = getArguments() != null ? getArguments().getString("nextAction") : "";

        // Inflate the layout for this fragment
        mCurrentView = inflater.inflate(R.layout.fragment_status, container, false);

        updateStatus(mActionType.equals(PassFlowActivity.ACTION_BLUETOOTH) ? R.string.text_status_message_scanning : R.string.text_status_message_waiting,
                "",
                R.drawable.waiting);

        startAction();

        return mCurrentView;
    }

    @Override
    public void onAttach(Context context) {
        super.onAttach(context);

        if (context instanceof FragmentActivity){
            mActivity = (FragmentActivity)context;

            if (mWaitingUpdate != null) {
                updateStatus(mWaitingUpdate.messageId, mWaitingUpdate.messageText, mWaitingUpdate.icon);
            }
        }
    }

    @Override
    public void onDetach() {
        super.onDetach();
        mActivity = null;
    }

    private void startAction() {
        if (mActionType.equals(PassFlowActivity.ACTION_BLUETOOTH)) {
            runBluetooth();
        } else if (mActionType.equals(PassFlowActivity.ACTION_REMOTEACCESS)) {
            runRemoteAccess();
        }
    }

    private void runRemoteAccess() {
        BluetoothManager.getInstance().stopScan(true);

        RequestAccess request = new RequestAccess();
        request.accessPointId = mAccessPointId;
        request.clubMemberId = ConfigurationManager.getInstance().getMemberId();
        request.direction = mDirection;

        new AccessPointService().remoteOpen(request, new BaseService.ServiceResultListener() {
            @Override
            public void onCompleted(Object result) {
                updateStatus( R.string.text_status_message_succeed,"", R.drawable.success);
                DelegateManager.getInstance().onCompleted(true);
            }

            @Override
            public void onError(int statusCode, String message) {
                if (statusCode != 401 && mNextAction != null && mNextAction.equals(PassFlowActivity.ACTION_BLUETOOTH)) {
                    updateStatus( R.string.text_status_message_scanning, "",  R.drawable.waiting);
                    runBluetooth();
                } else {
                    if (message == null || message.isEmpty()) {
                        int failMessage = R.string.text_status_message_failed;

                        if (statusCode == 401) {
                            failMessage = R.string.text_status_message_unauthorized;
                        } else if (statusCode == 404) {
                            failMessage = R.string.text_status_message_not_connected;
                        } else if (statusCode == 0) {
                            failMessage = R.string.text_status_message_no_connection;
                        }

                        updateStatus(failMessage, "", R.drawable.error);
                    } else {
                        updateStatus(-1, message, R.drawable.error);
                    }
                    DelegateManager.getInstance().onCompleted(false);
                }
            }
        });
    }

    private void runBluetooth() {
        BluetoothManager.getInstance().delegate = this;

        if (BluetoothManager.getInstance().getCurrentState().enabled) {
            updateStatus( R.string.text_status_message_scanning, "", R.drawable.waiting);

            BLEScanConfiguration config = new BLEScanConfiguration(mDevices, ConfigurationManager.getInstance().getMemberId(), mDeviceNumber, mDirection, mRelayNumber);

            BluetoothManager.getInstance().startScan(config);
            startBluetoothTimer();
        } else {
            if (ConfigurationManager.getInstance().waitForBLEEnabled() || mNextAction == null) {
                DelegateManager.getInstance().onNeedPermission(NeedPermissionType.NEED_ENABLE_BLE);
                updateStatus( R.string.text_status_message_need_ble_enabled,"", R.drawable.warning);
            } else {
                onBluetoothConnectionFailed(false);
            }
        }
    }

    private void startBluetoothTimer() {
        mTimerHandler =  new Handler();
        Runnable mTimerRunnable = new Runnable() {
            public void run() {
                onBluetoothConnectionFailed(true);
            }
        };

        mTimerHandler.postDelayed(mTimerRunnable, ConfigurationManager.getInstance().getBLEConnectionTimeout() * 1000);
    }

    private void endBluetoothTimer() {
        if (mTimerHandler != null) {
            mTimerHandler.removeCallbacksAndMessages(null);
        }
    }

    private void onBluetoothConnectionFailed(boolean timeout) {
        if (timeout) {
            LogManager.getInstance().debug("Timeout occurred for BLE scanning");
        }

        BluetoothManager.getInstance().delegate = null;
        BluetoothManager.getInstance().stopScan(true);

        if (mNextAction != null && mNextAction.length() > 0) {
            if (mNextAction.equals(PassFlowActivity.ACTION_LOCATION)) {
                DelegateManager.getInstance().flowNextActionRequired();
            } else if (mNextAction.equals(PassFlowActivity.ACTION_REMOTEACCESS)) {
                updateStatus(R.string.text_status_message_waiting,"", R.drawable.waiting);
                runRemoteAccess();
            }
        } else {
            updateStatus( R.string.text_status_message_failed, "", R.drawable.error);
            DelegateManager.getInstance().onCompleted(false);
        }
    }

    private void updateStatus(final int messageId, final String messageText, final @Nullable Integer icon) {
        if (mActivity != null) {
            mWaitingUpdate = null;
            mActivity.runOnUiThread(new Runnable() {

                @Override
                public void run() {
                    /*
                    ConstraintLayout statusBackground = mCurrentView.findViewById(R.id.status_background);
                    statusBackground.setBackgroundResource(background);
                     */

                    /*
                    ProgressBar spinner = mCurrentView.findViewById(R.id.progressBar);
                    spinner.setVisibility(showSpinner ? View.VISIBLE : View.GONE);
                     */

                    ImageView statusIcon = mCurrentView.findViewById(R.id.imgStatusIcon);

                    if (icon != null) {
                        statusIcon.setImageResource(icon);
                    }

                    // statusIcon.setVisibility(showSpinner ? View.GONE : View.VISIBLE);

                    TextView statusMessage = mCurrentView.findViewById(R.id.txtStatusMessage);
                    if (messageId != -1) {
                        statusMessage.setText(messageId);
                    } else {
                        statusMessage.setText(messageText);
                    }
                }
            });
        } else {
            mWaitingUpdate = new WaitingStatusUpdate(messageId, messageText, icon);
        }
    }

    @Override
    public void onConnectionStateChanged(DeviceConnectionStatus state) {
        if (state.state != DeviceConnectionStatus.ConnectionState.CONNECTING) {
            this.endBluetoothTimer();
        }

        if (state.state == DeviceConnectionStatus.ConnectionState.CONNECTED) {
            updateStatus( R.string.text_status_message_succeed, "", R.drawable.success);
            DelegateManager.getInstance().onCompleted(true);
        } else if (state.state == DeviceConnectionStatus.ConnectionState.FAILED
                || state.state == DeviceConnectionStatus.ConnectionState.NOT_FOUND
                || (mLastConnectionState == DeviceConnectionStatus.ConnectionState.CONNECTING && state.state == DeviceConnectionStatus.ConnectionState.DISCONNECTED)) {

            onBluetoothConnectionFailed(false);
        }

        mLastConnectionState = state.state;
    }

    @Override
    public void onBLEStateChanged(DeviceCapability state) {
        if (mActionType != null && mActionType == PassFlowActivity.ACTION_BLUETOOTH && !mLastBluetoothState && state.enabled) {
            mLastBluetoothState = true;
            runBluetooth();
        } else {
            mLastBluetoothState = state.enabled;
        }
    }
}
