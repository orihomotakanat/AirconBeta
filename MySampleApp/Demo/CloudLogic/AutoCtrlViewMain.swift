//
//  AutoCtrlViewMain.swift
//  MySampleApp
//
//  Created by Tanaka, Tomohiro on 2017/05/04.
//
//
import Foundation
import UIKit
import SwiftyJSON
import AWSIoT
import AWSCore
import AWSCognito
import KRProgressHUD
import NVActivityIndicatorView

class AutoCtrlViewMain: UIViewController {
    
    var count: Int = 0 //タイマーのカウント
    var hour: Int = 0 //Hour
    var min: Int = 0 //Min
    var sec: Int = 0 //Second
    
    var currentTime = Timer() //現在の時間
    
    var reservedConfirmation = true //trueの時1回目のカウントの時
    var alreadyStartedTimer = true //trueの時はまだOnになってないorOFFが押された時、falseの時はTimerが動いている時
    var timerIdentifier = true

    
    @IBOutlet var reservedTimer: UIDatePicker!
    //タイマー関連の設置
    @IBOutlet var hourView: UILabel!
    @IBOutlet var minView: UILabel!
    @IBOutlet var hourUnit: UILabel!
    @IBOutlet var minUnit: UILabel!
    @IBOutlet var secView: UILabel!
    
    //Button関連設定
    @IBOutlet var ReserveOnButton: UIButton!
    @IBOutlet var onButton: UIButton!
    @IBOutlet var offButton: UIButton!
    @IBOutlet var ReserveOffButton: UIButton!
    
    
    //MQTT通信
    var iotDataManager: AWSIoTDataManager!
    
    //underOps用
    @IBOutlet var underOpsView: NVActivityIndicatorView!
    
    //TapticEngine
    let tapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
    let tapticNotficationGenerator = UINotificationFeedbackGenerator()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tapticGenerator.prepare() //tapticEngineの準備
        tapticNotficationGenerator.prepare() //reserveTimer用tapticEngineの準備

        //NavigationBar
        navigationItem.backBarButtonItem = UIBarButtonItem(title: "Back", style: .plain, target: nil, action: nil)
        reservedTimer.setValue(UIColor.white, forKey: "textColor")
        self.navigationItem.title = "AIRCON"
        
        
        //設定Timerの非表示化
        hourView.isHidden = true
        minView.isHidden = true
        hourUnit.isHidden = true
        minUnit.isHidden = true
        secView.isHidden = true

        
        //ReserveOffButtonとOffButtonの非表示化
        ReserveOffButton.isHidden = true
        offButton.isHidden = true
        
        
        //Indicatorのサイズ設定
        KRProgressHUD.set(style: .custom(background: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1).withAlphaComponent(0.9), text: #colorLiteral(red: 0.1658749767, green: 0.9686274529, blue: 0.6630814156, alpha: 1), icon: #colorLiteral(red: 0.1658749767, green: 0.9686274529, blue: 0.6630814156, alpha: 1))) //indicatorのHUD(バックの四角) background.clear: HUD->clear, text, icon: 今回表示していないので特に問題なし
        KRProgressHUD.set(activityIndicatorViewStyle: .gradationColor(head: #colorLiteral(red: 0.1658749767, green: 0.9686274529, blue: 0.6630814156, alpha: 1), tail: #colorLiteral(red: 0.03894692283, green: 0.5160927344, blue: 0.9686274529, alpha: 1)))
        KRProgressHUD.set(maskType: .clear) //画面をマスクするか->今回はなし
        KRProgressHUD.show(withMessage: "Connecting device") //indicatorの表示 -> インジケータの表示の終了はグラフ表示直前で行う
    
        
        //MQTT用Websocket
        iotDataManager = AWSIoTDataManager.default()
        iotDataManager.connectUsingWebSocket(withClientId: UUID().uuidString, cleanSession: true, statusCallback: mqttEventCallback)
        
        //UnderOperation用indicator
        underOpsView.type = .ballScaleMultiple //表示typeの設定
        underOpsView.color = #colorLiteral(red: 0.1658749767, green: 0.9686274529, blue: 0.6630814156, alpha: 1)
        
    }
    
    
    //Airconの電源オンにする
    func turnOnAircon() {
        print("Sended turn on")
        iotDataManager.publishString("turn on", onTopic:"sampletopic", qoS:.messageDeliveryAttemptedAtMostOnce)
        iotDataManager.publishString("1", onTopic:"sampletopic", qoS: .messageDeliveryAttemptedAtMostOnce) //kinesisに対しairconの状態を送る
        underOpsView.startAnimating() //underOps start
    }
    
    
    //Airconの電源オフにする
    func turnOffAircon() {
        print("Sended turn off")
        iotDataManager.publishString("turn off", onTopic:"sampletopic", qoS:.messageDeliveryAttemptedAtMostOnce)
        iotDataManager.publishString("0", onTopic:"sampletopic", qoS: .messageDeliveryAttemptedAtMostOnce) //kinesisに対しairconの状態を送る
        underOpsView.stopAnimating() //underOps finish
    }
    
    
    //Reserve buttonが押されたときに始動する
    @IBAction func startTimer(sender: AnyObject) {
        
        if alreadyStartedTimer {
            currentTime = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(self.passed), userInfo: nil, repeats: true)
            alreadyStartedTimer = false
            
            //OnButton->Off, ReserveOnButton->ReserveOffButtonへ
            onButton.isHidden = true
            offButton.isHidden = false
            ReserveOnButton.isHidden = true
            ReserveOffButton.isHidden = false
            
            
        }
        //TapticEngineの設定
        tapticGenerator.impactOccurred()
        tapticGenerator.impactOccurred()//２つ並べてちょっと重めにする
        
    }
    
    
    //reserve Timer用の設定
    func passed(timeCount: Timer){
        if reservedConfirmation {
            count = Int(reservedTimer.countDownDuration)
            
            //Timerの表示
            reservedTimer.isHidden = true   //Timer部分の非表示
            hourView.isHidden = false
            minView.isHidden = false
            hourUnit.isHidden = false
            minUnit.isHidden = false
            secView.isHidden = false
            
            reservedConfirmation = false
        }
        
        hour = Int(count/3600) //Hour
        min = Int((count - hour * 3600) / 60) //Min
        sec = Int(count - hour*3600 - min*60) //sec
        count = count - 1
        //Timer設定
        if count == 0 {
            //ここにAirconの機能を入れる
            turnOnAircon()
            
            tapticNotficationGenerator.notificationOccurred(.success)
            currentTime.invalidate() //Timer停止
            reservedConfirmation = true //reserveされていない状態に戻す
            alreadyStartedTimer = true //timerが作動していない状態に戻す
            
            //ON表示
            hourView.isHidden = true
            minView.isHidden = true
            hourUnit.isHidden = true
            minUnit.isHidden = true
            secView.isHidden = true

            
            
            print("Timer is stopped & Start Aircon")
        } else {
            hourView.text = String(format: "%02d", hour) //タイマーのカウントする
            minView.text = String(format: "%02d", min)
            secView.text = String(format: "%02d", sec)
            print(count) //For debug

        }
    }
    
    @IBAction func turnOn(_ sender: Any) {
        //Timer関連の設定
        reservedTimer.isHidden = true
        hourView.isHidden = true
        minView.isHidden = true
        hourUnit.isHidden = true
        minUnit.isHidden = true
        secView.isHidden = true
        
        //ここにAirconの機能を入れる
        turnOnAircon ()
        
        //Buttonの設定(ReservedOnButton->ReservedOffButton, onButton->offButtonへ
        ReserveOnButton.isHidden = true
        ReserveOffButton.isHidden = false
        onButton.isHidden = true
        offButton.isHidden = false
        
        
        reservedConfirmation = false
        currentTime.invalidate()
        
        
        //TapticEngineの設定
        tapticGenerator.impactOccurred()
        tapticGenerator.impactOccurred()//２つ並べてちょっと重めにする
    }
    
    //MQTTcallback for debug
    func mqttEventCallback( _ status: AWSIoTMQTTStatus )
    {
        DispatchQueue.main.async {
            print("connection status = \(status.rawValue)")
            switch(status)
            {
            case .connecting:
                print( "Connecting..." )
                
            case .connected:
                
                print( "Connected" )
                //
                // Register the device shadows once connected.
                //
                let statusThingName="AirconRasPi"
                self.iotDataManager.getShadow(statusThingName)
                sleep(1)
                KRProgressHUD.showSuccess(withMessage: "Successful connection")
                
            case .disconnected:
                print( "Disconnected" )
                
            case .connectionRefused:
                print( "Connection Refused" )
                
            case .connectionError:
                print( "Connection Error" )
                
            case .protocolError:
                print( "Protocol Error" )
                
            default:
                print("unknown state: \(status.rawValue)")
            }
        }
    }

    
    
    @IBAction func turnOff(sender: AnyObject) {
        //Timer関連の設定
        reservedTimer.isHidden = false
        hourView.isHidden = true
        minView.isHidden = true
        hourUnit.isHidden = true
        minUnit.isHidden = true
        secView.isHidden = true

        
        //ここにAirconの機能を入れる
        turnOffAircon ()
        
        
        
        //Button関連の設置(ReserveOffButton->ReserveOnButton, OffButton->OnButtonへ)
        ReserveOffButton.isHidden = true
        ReserveOnButton.isHidden = false
        offButton.isHidden = true
        onButton.isHidden = false
        
        currentTime.invalidate() //TimerをOFFにする
        reservedConfirmation = true //reserveされていない状態に戻す
        alreadyStartedTimer = true //timerが作動していない状態に戻す
        
        tapticGenerator.impactOccurred()
        tapticGenerator.impactOccurred() //２つ並べてちょっと重めにする
    }
    

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
}
