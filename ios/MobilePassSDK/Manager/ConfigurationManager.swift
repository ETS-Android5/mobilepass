//
//  ConfigurationManager.swift
//  MobilePassSDK
//
//  Created by Erinc Cakir on 17.02.2021.
//

import Foundation

enum ConfigurationError: Error {
    case validationError(String)
}

class ConfigurationManager: NSObject {
    
    // MARK: Singleton
    
    static let shared = ConfigurationManager()
    private override init() {
        super.init()
        LogManager.shared.info(message: "Setting up Configuration Manager instance")
    }
    
    // MARK: Private Fields
    
    private var mCurrentConfig:     Configuration?
    private var mCurrentKeyPair:    CryptoKeyPair?
    private var mCurrentQRCodes:    Dictionary<String, QRCodeContent> = [:]
    private var mTempQRCodes:       Dictionary<String, QRCodeContent> = [:]
    private var mPagination:        RequestPagination? = nil
    private var mListSyncDate:      Int64? = nil
    private var mReceivedItemCount: Int = 0
    private var mUserKeyDetails:    [StorageDataUserDetails] = []
    
    // MARK: Public Methods
    
    public func setConfig(data: Configuration) throws -> Void {
        mCurrentConfig = data
        
        getStoredQRCodes()
        
        try validateConfig()
        try sendUserData()
    }
    
    public func setToken(token: String, language: String) throws -> Void {
        if (mCurrentConfig != nil) {
            mCurrentConfig!.token = token
            mCurrentConfig!.language = language
            
            try sendUserData();
        }
    }
    
    public func getQRCodeContent(qrCodeData: String) -> QRCodeContent? {
        return mCurrentQRCodes.index(forKey: qrCodeData) != nil ? mCurrentQRCodes[qrCodeData]! : nil
    }
    
    public func getMemberId() -> String {
        return mCurrentConfig?.memberId ?? ""
    }
    
    public func getPrivateKey() -> String {
        return mCurrentKeyPair?.privateKey ?? ""
    }
    
    public func getServerURL() -> String {
        var serverUrl: String = mCurrentConfig?.serverUrl ?? ""
        
        if (serverUrl.count > 0 && !serverUrl.hasSuffix("/")) {
            serverUrl += "/"
        }
        
        return serverUrl
    }
    
    public func getMessageQRCode() -> String {
        return mCurrentConfig?.qrCodeMessage ?? ""
    }
    
    public func getToken() -> String {
        return mCurrentConfig?.token ?? "unknown"
    }
    
    public func getLanguage() -> String {
        return mCurrentConfig?.language ?? "en"
    }
    
    public func isMockLocationAllowed() -> Bool {
        return mCurrentConfig?.allowMockLocation ?? false
    }
    
    public func bleConnectionTimeout() -> Int {
        return mCurrentConfig?.connectionTimeout ?? 5
    }
    
    public func autoCloseTimeout() -> Int? {
        return mCurrentConfig?.autoCloseTimeout
    }
    
    public func waitForBLEEnabled() -> Bool {
        return mCurrentConfig?.waitBLEEnabled ?? false
    }
    
    // MARK: Private Methods
    
    private func getStoredQRCodes() -> Void {
        _ = try? StorageManager.shared.deleteValue(key: StorageKeys.QRCODES, secure: false)
        
        let storageQRCodes: String? = try? StorageManager.shared.getValue(key: StorageKeys.LIST_QRCODES, secure: false)
        mCurrentQRCodes = (storageQRCodes != nil && storageQRCodes!.count > 0 ? try? JSONUtil.shared.decodeJSONData(jsonString: storageQRCodes!) : [:]) ?? [:]
    }
    
    private func validateConfig() throws -> Void {
        if (mCurrentConfig == nil) {
            throw ConfigurationError.validationError("Configuration is required for MobilePass");
        }
        
        if (mCurrentConfig?.memberId == nil || mCurrentConfig?.memberId.count == 0) {
            throw ConfigurationError.validationError("Provide valid Member Id to continue, received data is empty!");
        }
        
        if (mCurrentConfig?.serverUrl == nil || mCurrentConfig?.serverUrl.count == 0) {
            throw ConfigurationError.validationError("Provide valid Server URL to continue, received data is empty!");
        }
    }
    
    private func checkKeyPair() throws -> Bool {
        mCurrentKeyPair = nil
        
        var newlyCreated: Bool = false
        let storedUserKeys: String = try StorageManager.shared.getValue(key: StorageKeys.USER_DETAILS, secure: true)
        
        if (storedUserKeys.count > 0) {
            mUserKeyDetails = try JSONUtil.shared.decodeJSONArray(jsonString: storedUserKeys)
            
            for user in mUserKeyDetails {
                if (user.userId == getMemberId()) {
                    mCurrentKeyPair = CryptoKeyPair(publicKey: user.publicKey, privateKey: user.privateKey)
                    break
                }
            }
        }
        
        if (mCurrentKeyPair == nil) {
            newlyCreated = true
            
            mCurrentKeyPair = CryptoManager.shared.generateKeyPair()
            
            mUserKeyDetails.append(StorageDataUserDetails(userId: getMemberId(), publicKey: mCurrentKeyPair!.publicKey, privateKey: mCurrentKeyPair!.privateKey))
            let jsonString = try JSONUtil.shared.encodeJSONArray(data: mUserKeyDetails)
            
            _ = try StorageManager.shared.setValue(key: StorageKeys.USER_DETAILS, value: jsonString, secure: true)
        }
        
        return newlyCreated
    }
    
    private func sendUserData() throws -> Void {
        var needUpdate: Bool = try checkKeyPair();
        
        let storedMemberId: String? = try? StorageManager.shared.getValue(key: StorageKeys.MEMBERID, secure: false)
        if (storedMemberId == nil || storedMemberId!.count == 0 || storedMemberId! != getMemberId()) {
            needUpdate = true
        }
        
        if (needUpdate) {
            DataService().sendUserInfo(request: RequestSetUserData(publicKey: mCurrentKeyPair!.publicKey, clubMemberId: getMemberId()), completion: { (result) in
                if case .success(_) = result {
                    do {
                        _ = try StorageManager.shared.setValue(key: StorageKeys.MEMBERID, value: self.getMemberId(), secure: false)
                        LogManager.shared.info(message: "Member id is stored successfully")
                    } catch {
                        LogManager.shared.error(message: "Error occurred while storing member id")
                    }
                    self.getAccessPoints()
                } else {
                    LogManager.shared.error(message: "Send user info to server failed!")
                    self.getAccessPoints()
                }
            })
        } else {
            LogManager.shared.info(message: "User info is already sent to server")
            self.getAccessPoints()
        }
    }
    
    private func processQRCodesResponse(result: Result<ResponseAccessPointList?, RequestError>) {
        if case .success(let receivedData) = result {
            if (receivedData == nil) {
                LogManager.shared.error(message: "Empty data received for access points list")
                return
            }
            
            self.mReceivedItemCount += receivedData!.items.count
            
            for item in (receivedData?.items ?? []) {
                for qrCode in item.q {
                    let content = QRCodeContent(terminals: item.t, qrCode: qrCode, geoLocation: item.g)
                    self.mTempQRCodes[qrCode.q] = content
                }
            }
            
            /* Open to show qr codes list
            for qrCode in self.mTempQRCodes {
                LogManager.shared.debug(message: "\(qrCode.key) > Type: \(qrCode.value.action.config.trigger.type) | Direction: \(qrCode.value.action.config.direction) | Validate Location: \(String(describing: qrCode.value.action.config.trigger.validateGeoLocation))")
            }
            */
            
            
            if (receivedData!.pagination.total > self.mReceivedItemCount) {
                self.mPagination?.skip = self.mReceivedItemCount
                self.fetchAccessPoints()
            } else {
                self.mCurrentQRCodes = [:]
                
                for qrCode in self.mTempQRCodes {
                    self.mCurrentQRCodes[qrCode.key] = qrCode.value
                }
                
                do {
                    let valueQRCodesToStore: String? = try? JSONUtil.shared.encodeJSONData(data: self.mCurrentQRCodes)
                    _ = try StorageManager.shared.setValue(key: StorageKeys.LIST_QRCODES, value: valueQRCodesToStore ?? "", secure: false)
                    _ = try StorageManager.shared.setValue(key: StorageKeys.LIST_SYNC_DATE, value: (Int64(Date().timeIntervalSince1970 * 1000)).description, secure: false)
                } catch {
                    LogManager.shared.error(message: "Store received access list failed!")
                }
                
                DelegateManager.shared.qrCodeListChanged(state: self.mCurrentQRCodes.count > 0 ? QRCodeListState.USING_SYNCED_DATA : QRCodeListState.EMPTY)
            }
        } else {
            LogManager.shared.error(message: "Get access list failed!")
            DelegateManager.shared.qrCodeListChanged(state: self.mCurrentQRCodes.count > 0 ? QRCodeListState.USING_STORED_DATA : QRCodeListState.EMPTY)
        }
    }
    
    private func fetchAccessPoints() -> Void {
        DataService().getAccessList(pagination: self.mPagination!, syncDate: self.mListSyncDate, completion: { (result) in
            self.processQRCodesResponse(result: result)
        })
    }
    
    private func getAccessPoints() -> Void {
        DelegateManager.shared.qrCodeListChanged(state: .SYNCING)
        
        let storedSyncDate: String? = try? StorageManager.shared.getValue(key: StorageKeys.LIST_SYNC_DATE, secure: false)
        
        if (storedSyncDate != nil) {
            self.mListSyncDate = Int64(storedSyncDate!)
        }
        
        self.mPagination = RequestPagination(take: 100, skip: 0)
        
        self.mTempQRCodes = [:]
        self.mReceivedItemCount = 0
        
        self.fetchAccessPoints()
    }
    
}
