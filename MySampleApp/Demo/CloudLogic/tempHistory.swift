//
//  tempHistory.swift
//  MySampleApp
//
//  Created by Tanaka, Tomohiro on 2017/05/04.
//
//

import Foundation
import UIKit
import AWSMobileHubHelper
import AWSAPIGateway
import SwiftyJSON
import Charts
import KRProgressHUD
import AWSIoT
import NVActivityIndicatorView


var timeHisArray: [Int] = []

class tempHistory: UIViewController {
    
    //MQTT通信
    var iotDataManager: AWSIoTDataManager!
    
    
    //APIGatewayをたたく上で必要なParameter
    let apiEp = "apiEndPoint"
    let toLambdaPath = "/lambdaPath"
    let queryStringParam = "TableName=sample" //
    let apiCli = xxx_LambdaMicroserviceClient(forKey: AWSCloudLogicDefaultConfigurationKey)
    
    var cloudLogicAPI: CloudLogicAPI?
    
    //LineChart to get graph of time and temperature History
    @IBOutlet var tempHistoryGraph: LineChartView! {
        didSet {
            //x軸設定
            tempHistoryGraph.xAxis.labelPosition = .bottom //x軸ラベル下側に表示
            tempHistoryGraph.xAxis.labelFont = UIFont.systemFont(ofSize: 11) //x軸のフォントの大きさ
            tempHistoryGraph.xAxis.labelCount = Int(4)
            tempHistoryGraph.xAxis.labelTextColor = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1) //x軸ラベルの色
            tempHistoryGraph.xAxis.axisLineColor = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1) //x軸の色
            tempHistoryGraph.xAxis.axisLineWidth = CGFloat(1) //x軸の太さ
            tempHistoryGraph.xAxis.drawGridLinesEnabled = false //x軸のグリッド表示(今回は表示しない)
            tempHistoryGraph.xAxis.valueFormatter = lineChartFormatter() //x軸の仕様
            
            
            //y軸設定
            //tempHistoryGraph.leftAxis.drawTopYLabelEntryEnabled = true //y軸の最大値のみ表示
            tempHistoryGraph.rightAxis.enabled = false //右軸の表示
            tempHistoryGraph.leftAxis.enabled = true //左軸の表示
            tempHistoryGraph.leftAxis.axisMaximum = 40 //y左軸最大値
            tempHistoryGraph.leftAxis.axisMinimum = 0 //y左軸最小値
            tempHistoryGraph.leftAxis.labelFont = UIFont.systemFont(ofSize: 11) //y左軸のフォントの大きさ
            tempHistoryGraph.leftAxis.labelTextColor = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1) //y軸ラベルの色
            tempHistoryGraph.leftAxis.axisLineColor = #colorLiteral(red: 0.05882352963, green: 0.180392161, blue: 0.2470588237, alpha: 1) //y左軸の色(今回はy軸消すためにBGと同じ色にしている)
            tempHistoryGraph.leftAxis.drawAxisLineEnabled = false //y左軸の表示(今回は表示しない)
            tempHistoryGraph.leftAxis.labelCount = Int(4) //y軸ラベルの表示数
            tempHistoryGraph.leftAxis.drawGridLinesEnabled = true //y軸のグリッド表示(今回は表示する)
            tempHistoryGraph.leftAxis.gridColor = #colorLiteral(red: 0.6000000238, green: 0.6000000238, blue: 0.6000000238, alpha: 1) //y軸グリッドの色
            
            //その他UI設定
            tempHistoryGraph.noDataFont = UIFont.systemFont(ofSize: 30) //Noデータ時の表示フォント
            tempHistoryGraph.noDataTextColor = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1) //Noデータ時の文字色
            tempHistoryGraph.noDataText = ""//"Keep Waiting" //Noデータ時に表示する文字 今回はインジケータで表示するのでなし
            tempHistoryGraph.legend.enabled = false //"■ months"のlegendの表示
            tempHistoryGraph.dragDecelerationEnabled = true //指を離してもスクロール続くか
            tempHistoryGraph.dragDecelerationFrictionCoef = 0.6 //ドラッグ時の減速スピード(0-1)
            tempHistoryGraph.chartDescription?.text = nil //Description(今回はなし)
            tempHistoryGraph.backgroundColor = #colorLiteral(red: 0.05882352963, green: 0.180392161, blue: 0.2470588237, alpha: 1) //Background Color
            //.animateは表示直前で呼ぶためにグラフ描画の直前の部分かく
            
        }
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        //Indicatorのサイズ設定
        KRProgressHUD.set(style: .custom(background: .clear, text: .clear, icon: nil)) //indicatorのHUD(バックの四角) background.clear: HUD->clear, text, icon: 今回表示していないので特に問題なし
        KRProgressHUD.set(activityIndicatorViewStyle: .gradationColor(head: #colorLiteral(red: 0.1658749767, green: 0.9686274529, blue: 0.6630814156, alpha: 1), tail: #colorLiteral(red: 0.03894692283, green: 0.5160927344, blue: 0.9686274529, alpha: 1)))
        KRProgressHUD.set(maskType: .clear) //画面をマスクするか->今回はなし
        
        KRProgressHUD.show() //indicatorの表示 -> インジケータの表示の終了はグラフ表示直前で行う
        
        //MQTT用Websocket
        iotDataManager = AWSIoTDataManager.default()
        iotDataManager.connectUsingWebSocket(withClientId: UUID().uuidString, cleanSession: true, statusCallback: mqttEventCallback)
        
        outputDynamoDBdata()

    }
    
 
//Drawing Graphs
    func outputDynamoDBdata () {
        
        var tempHisArray: [Double] = [] //温度分布表示用の配列
        var dynamoDictionary: [Int: Double] = [:] //時間と温度のペア
        
//ここからdynamoのデータ取ってくる用*******************************************************************
        let headerParameters = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
        var queryParameters = [String: String]()
        
        let keyValuePairStringArray = queryStringParam.components(separatedBy: "&")
        
        for pairString in keyValuePairStringArray {
            let keyValue = pairString.components(separatedBy: "=")
            queryParameters.updateValue(keyValue[1], forKey: keyValue[0])
        }
        
        let apiRequest = AWSAPIGatewayRequest(httpMethod: "GET", urlString: toLambdaPath, queryParameters: queryParameters, headerParameters: headerParameters, httpBody: nil)
        
        //lambdaにinvoke(今回はGETのみ)
        apiCli.invoke(apiRequest).continueWith(block: {[weak self](task: AWSTask) -> AnyObject? in
            //guard let strongSelf = self else { return nil } //一応下になってるけど怖いので置いておきます
            guard self != nil else { return nil }
            
            let result: AWSAPIGatewayResponse! = task.result
            //let responseString = String(data: result.responseData!, encoding: String.Encoding.utf8)
            
            //print(responseString!)
            //print(result.statusCode) //statuscode返す200でok
            
            //以下SwiftyJsonによりparseする
            var outputJson = JSON(data: result.responseData!)
            let arr_num = Int(outputJson["Items"].count)

            
            //現在時刻を取得(unixtime -> Int)
            let currentTime = Date().timeIntervalSince1970
            //DynamoDBから取ってくる3days分の時間
            let timeHistoryRange: Int = Int(currentTime) - 86400//=1day//172800 //=2days //28800 //ForDebug(8h)
            
            //DynamoDBからtimestampとtemperatureを取ってくる
            if arr_num <= 1 {
                print("Error")
            } else {
                for element in 0...arr_num-1 {
                    //if 3day前以外のデータはappendしない様に設定する curretUnixTime - unixtimeFromDynamo <= 3day
                    if outputJson["Items"][element]["time"].intValue >= timeHistoryRange {
                        let timeFromDynamo = outputJson["Items"][element]["time"].intValue //dyanmoからの時間データ
                        let tempFromDynamo = outputJson["Items"][element]["value"]["temp"].doubleValue //dynamoからの温度データ
                        dynamoDictionary[timeFromDynamo] = tempFromDynamo //key-value式で各時間に対する温度を格納
                    }
                }
            }
            
            KRProgressHUD.dismiss() //インジケータ消す
            
            //時間と温度を取り出す
            for (time, temp) in dynamoDictionary.sorted(by: {$0 < $1}) {
                timeHisArray.append(time)
                tempHisArray.append(temp)
            }
            
            //ここが非同期処理部分
            //DispatchQueue.global(qos: .default).async { //(サブスレッド=Backgroud)
            //DispatchQueue.main.async { //(メインスレッド）
            
            self?.drawLineChart(xValArr: timeHisArray, yValArr: tempHisArray)
            //}
            return nil
        }) //apiCli.invoke... end
    } //func outputDynamoDBdata () { end
    
    
    
//以下からグラフ作成部分*****************************************************************************
    func drawLineChart(xValArr: [Int], yValArr: [Double]) {
        
        var yValues : [ChartDataEntry] = [ChartDataEntry]()
        
        for i in 0 ..< xValArr.count {
            let dataEntry = ChartDataEntry(x: Double(i), y: yValArr[i])
            yValues.append(dataEntry) //(ChartDataEntry(x: Double(i), y: dollars1[i]))
        }

        let data = LineChartData()
        let ds = LineChartDataSet(values: yValues, label: "Dates") //ds means DataSet
        
//グラフのUI設定************************************************************************************
        //グラフのグラデーション有効化
        let gradientColors = [#colorLiteral(red: 1, green: 1, blue: 1, alpha: 1).cgColor, #colorLiteral(red: 0.2196078449, green: 1, blue: 0.8549019694, alpha: 1).withAlphaComponent(0.3).cgColor] as CFArray // Colors of the gradient
        let colorLocations:[CGFloat] = [0.7, 0.0] // Positioning of the gradient
        let gradient = CGGradient.init(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gradientColors, locations: colorLocations) // Gradient Object
        //yourDataSetName.fill = Fill.fillWithLinearGradient(gradient!, angle: 90.0) // Set the Gradient
        ds.fill = Fill.fillWithLinearGradient(gradient!, angle: 90.0) // Set the Gradient
        //その他UI設定
        ds.lineWidth = 3.0 //線の太さ
        //ds.circleRadius = 0 //プロットの大きさ
        ds.drawCirclesEnabled = false //プロットの表示(今回は表示しない)
        ds.mode = .cubicBezier //曲線にする
        ds.fillAlpha = 0.8 //グラフの透過率(曲線は投下しない)
        ds.drawFilledEnabled = true //グラフ下の部分塗りつぶし
        //ds.fillColor = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1) //グラフ塗りつぶし色(ただしlineChartSet.drawFilledEnabled = trueになっている必要がある)
        ds.drawValuesEnabled = false //各プロットのラベル表示(今回は表示しない)
        ds.highlightColor = #colorLiteral(red: 1, green: 0.8392156959, blue: 0.9764705896, alpha: 1) //各点を選択した時に表示されるx,yの線
        ds.colors = [#colorLiteral(red: 1, green: 1, blue: 1, alpha: 1)] //Drawing graph
//************************************************************************************グラフのUI設定
        
        data.addDataSet(ds)
        tempHistoryGraph.animate(xAxisDuration: 1.2, yAxisDuration: 1.5, easingOption: .easeInOutElastic)//animate(xAxisDuration: 5.0, yAxisDuration: 5.0, endAppearanceTransition()) //グラフのアニメーション(秒数で設定)
        self.tempHistoryGraph.data = data
    } //func drawLineChart(xValArr: [String], yValArr: [Double]) { End
    

    @IBOutlet var airconReadingView: NVActivityIndicatorView!
    @IBOutlet var currentSituation: UILabel!
    
    //For ML
    @IBAction func aircon(_ sender: Any) {
        airconReadingView.type = .ballScaleRippleMultiple
        airconReadingView.color = #colorLiteral(red: 0.1658749767, green: 0.9686274529, blue: 0.6630814156, alpha: 1)
        airconReadingView.startAnimating()
        
        //MQTT経由で現在のデータを取ってくる
        iotDataManager.publishString("toRasPi", onTopic:"aws/things/AirconRasPi/receive", qoS:.messageDeliveryAttemptedAtMostOnce)
        sleep(1)
        iotDataManager.subscribe(toTopic: "aws/things/AirconRasPi/curretSituation", qoS: .messageDeliveryAttemptedAtMostOnce, messageCallback: { (payload) in
            //let stringValue = NSString(data: payload, encoding: String.Encoding.utf8.rawValue)!
            let currentSituation = JSON(data: payload)
            let currentTemp = currentSituation["temp"].stringValue
            let currentHumidity = currentSituation["humidity"].stringValue
            
            self.currentSituation.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.2)
            self.currentSituation.text = "現在の室温は\(currentTemp) ℃\n湿度は\(currentHumidity) %です"
        })
    }
    
    //Viewから離れた時にairconConcierge動作を止める
    override func viewWillDisappear(_ animated: Bool) {
        airconReadingView.stopAnimating()
        self.currentSituation.text = nil
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
                
                
                //
                // Register the device shadows once connected.
                //
                let statusThingName="AirconRasPi"
                self.iotDataManager.getShadow(statusThingName)
                print( "Connected" )
                
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
    
    
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()

    }
    
} //class tempHistory: UIViewController { End






