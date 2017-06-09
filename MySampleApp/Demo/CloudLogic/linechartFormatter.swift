//
//  linechartFormatter.swift
//  MySampleApp
//
//  Created by Tanaka, Tomohiro on 2017/05/27.
//
//

import Foundation
import UIKit
import AWSMobileHubHelper
import AWSAPIGateway
import SwiftyJSON
import Charts


var ctrl = 0

//Using format: string for xaxis of  temperature histrory figure
public class lineChartFormatter: NSObject, IAxisValueFormatter {
    
    public func showDate(dateArr: [Int]) -> [String] {
        var showedDateArr: [String] = [] //表示する日付
        let dateformatter = DateFormatter()
        dateformatter.dateFormat = "M/d\n" + "HH:mm"
        for dateElement in 0..<dateArr.count {
            let intToDate = Date(timeIntervalSince1970: TimeInterval(dateArr[dateElement]))
            let insertDateArr = dateformatter.string(from: intToDate)
            showedDateArr.append(insertDateArr)
        }

        return showedDateArr
    }
    
    
    public func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        var showedXaxis: [String] = showDate(dateArr: timeHisArray)
        
        //print(showedXaxis)
        return showedXaxis[Int(value)]
        //return showedXaxis[Int(value)%showedXaxis.count]
    }
}
