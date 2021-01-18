import UIKit
import CoreLocation
import UserNotifications
import MapKit

enum ActionIdentifier: String {
    case actionUseful
    case actionUseless
}

struct LogData: Codable{
    let datetime: Date
    let content: String
    let actionType: String
    let placeId: String
    let message: String
}

struct PlaceInfo: Codable{
    var place_name: String
    var lat: Double
    var lng: Double
    var review: String
    var place_iword: String
    var exhibit_name: String
    var exhibit_id: String
    var exhibit_iword: String
    var exhibit_image_url: String
    var kaisetsu: String
    
}

func ==(lhs: PlaceInfo, rhs: PlaceInfo) -> Bool {
    return lhs.place_name == rhs.place_name && lhs.exhibit_name == rhs.exhibit_name
}

class ViewController: UIViewController, CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
    var locationManager: CLLocationManager!
    var coordinate_last: CLLocationCoordinate2D!
    var actionUsefulCount: Int = 0
    var actionUselessCount: Int = 0
    var placeList: [PlaceInfo]!
    var placeListBefore: [PlaceInfo] = []
    let GEOFENCESIZEMAX = 19
    let NOTIFICATEONLYN = 25
    var counter = 0 //通知only組
    var shufflePlaceList: [PlaceInfo]! = []
    var logFileName: String! = ""
    let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        //appendingPathComponentでURL型の最後に文字列を連結できる
    
    
    override func viewDidLoad(){
        super.viewDidLoad()
        
        
        //logfile生成
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH:mm:ss"
        logFileName = "log_" + df.string(from: Date()) + ".txt"
        writeLog(content: "Enter", actionType: "", placeId: "", message: "")
        
        //appdalegate との橋渡し
        let appDelegate:AppDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.viewController = self

        // LocationManagerのインスタンスの生成
        locationManager = CLLocationManager()
        
        //位置情報サービスの確認
        CLLocationManager.locationServicesEnabled()
        
        // セキュリティ認証のステータス
        let status = CLLocationManager.authorizationStatus()
        if(status == CLAuthorizationStatus.notDetermined) {
            // 許可をリクエスト
            locationManager.requestWhenInUseAuthorization()
        }
        
        // 位置情報取得をユーザーに認証してもらう
        locationManager.requestAlwaysAuthorization()
        
        // LocationManagerの位置情報変更などで呼ばれるfunctionを自身で受けるように設定
        locationManager.delegate = self
        
        // 位置情報の更新検知を開始
        locationManager.startUpdatingLocation()
        
        // json データのデバッグ出力
        placeList = loadData()
        
        // ジオフェンス観測停止
        self.stopGeofenceMonitoringAll()
        
        // 差分(初期は上位20件)を観測開始
        self.startGeofenceMoniteringDifference(placeListDiff: placeList)
        
        // map にユーザ位置を表示する
        map.showsUserLocation = true
        /*
        //！！！！！！！！！通知ONLY組！！！！！！！！！
        
        shufflePlaceList = placeList.shuffled()

        Timer.scheduledTimer(
            timeInterval: 50.0,
            target: self,
            selector: #selector(self.sendPlaceAMinutes),
            userInfo: nil,
            repeats: true
        )
        */
        
    }
    
    @IBOutlet weak var latLabel: UILabel!
    @IBOutlet weak var lngLabel: UILabel!
    @IBOutlet weak var countAct1: UILabel!
    @IBOutlet weak var countAct2: UILabel!
    @IBOutlet weak var map: MKMapView!
    @IBAction func resetButton(_ sender: Any) {
        stopGeofenceMonitoringAll()
    }
    
    // MARK: - Monitering function


    //位置情報が更新された後の処理
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        coordinate_last = locations.last?.coordinate
        print("lat: " + coordinate_last.latitude.description )
        print("lng: " + coordinate_last.longitude.description )
        latLabel.text = coordinate_last.latitude.description
        lngLabel.text = coordinate_last.longitude.description
        //print(String(describing: type(of: locations.last?.coordinate)))
        //map の中心位置
        //map.setCenter(coordinate_last, animated: true)
        //sort
        placeList = sortByDistance(placeData: self.placeList)
        //観測再開
        let a = placeList.prefix(GEOFENCESIZEMAX).map{$0}
        let b = placeListBefore.prefix(GEOFENCESIZEMAX).map{$0}
        var diff = getDiff(a:b, b:a)
        stopGeofenceMoniteringDifference(placeListDiff: diff)
        diff = getDiff(a:a, b:b)
        startGeofenceMoniteringDifference(placeListDiff: diff)
        countAct1.text = String(actionUsefulCount)
        countAct2.text = String(actionUselessCount)
    }
    
    //地物のソート
    func sortByDistance(placeData: [PlaceInfo]) -> [PlaceInfo] {
        let sortedPlaceData = placeData.sorted(by: { (a, b) -> Bool in
            //placeinfo のエラーはもとのデータ構造に手をつけると解消できる
            return caluculateDistance(target1: a, target2: b)
        })
        return sortedPlaceData
    }
    
    //地物との距離計算比較
    func caluculateDistance(target1: PlaceInfo, target2: PlaceInfo) -> Bool {
        let distance1: Double = pow(target1.lat - coordinate_last.latitude, 2) + pow(target1.lng - coordinate_last.longitude, 2)
        let distance2: Double = pow(target2.lat - coordinate_last.latitude, 2) + pow(target2.lng - coordinate_last.longitude, 2)
        return distance1 < distance2
    }
    
    //diffとり
    func getDiff(a: [PlaceInfo], b: [PlaceInfo]) -> [PlaceInfo]{
        var diff: [PlaceInfo] = []
        for aElement in a{
            var flag: Bool = true
            for bElement in b{
                if aElement == bElement{
                    flag = false
                }
            }
            if flag{
                diff.append(aElement)
            }
        }
        return diff
    }
    
    //差分のジオフェンス設置
    func startGeofenceMoniteringDifference(placeListDiff: [PlaceInfo]){
        var count:Int = 0
        for placeInfo in placeListDiff {
            if count > GEOFENCESIZEMAX {
                break
            }
            print(placeInfo.place_name)
            // ジオフェンスのモニタリング開始：このファンクションは適宜ボタンアクションなどから呼ぶ様にする。
            self.startGeofenceMonitering(name: placeInfo.place_name, lat: placeInfo.lat, lng:placeInfo.lng)
            count += 1
            placeListBefore = placeList
        }
    }
    
    //ジオフェンス設置処理
    func startGeofenceMonitering(name: String, lat: Double, lng: Double) {
        // 位置情報の取得開始
        locationManager.startUpdatingLocation()
        
        // モニタリングしたい場所の緯度経度を設定
        let moniteringCoordinate = CLLocationCoordinate2DMake(lat, lng)
        //let moniteringCoordinate = CLLocationCoordinate2DMake(35.569785, 139.402728) //ファミマ
        
        // モニタリングしたい領域を作成
        let moniteringRegion = CLCircularRegion.init(center: moniteringCoordinate, radius: 100.0, identifier: name)

        // モニタリング開始
        locationManager.startMonitoring(for: moniteringRegion)
        //print(name, lat, lng)
    }
    
    //すべての領域観測停止
    func stopGeofenceMonitoringAll(){
        for region in self.locationManager.monitoredRegions{
            print("モニタリング停止", region.identifier)
            self.locationManager.stopMonitoring(for: region)
        }
    }
    
    //差分の領域観測停止
    func stopGeofenceMoniteringDifference(placeListDiff: [PlaceInfo]){
        for region in self.locationManager.monitoredRegions{
            for place in placeListDiff{
                if place.place_name == region.identifier{
                    print("モニタリング停止", region.identifier)
                    self.locationManager.stopMonitoring(for: region)
                }
            }
        }
    }
    
    //画像保存
    // DocumentディレクトリのfileURLを取得
    func getDocumentsURL() -> NSURL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] as NSURL
        return documentsURL
    }
    // ディレクトリのパスにファイル名をつなげてファイルのフルパスを作る
    func fileInDocumentsDirectory(filename: String) -> String {
        let fileURL = getDocumentsURL().appendingPathComponent(filename)
        return fileURL!.path
    }
    //画像を保存するメソッド
    func saveImage (image: UIImage, path: String ) -> Bool {
        let jpgImageData = image.jpegData(compressionQuality:0.5)
        do {
            try jpgImageData!.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            print(error)
            return false
        }
        return true
    }
    
    func imageLocalDownload(imgURLString: String, myImageName: String) -> Bool{
        let imgURL = URL(string: imgURLString)
        let imagePath = self.fileInDocumentsDirectory(filename: myImageName)
        //imageがない、urlが不正の場合にfalseを返す
        guard let data = try? Data(contentsOf: imgURL!) else { return false }
        let image = UIImage(data: data)
        saveImage(image: image!, path: imagePath)
        return true
    }
    
    func getImagePath(imageName: String) -> URL{
        let documentDirectoryFileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last
            // ディレクトリのパスにファイル名をつなげてファイルのフルパスを作る
        let targetImageFilePath = documentDirectoryFileURL!.appendingPathComponent(imageName)
        return targetImageFilePath
    }
    
    func appendImageToContents(imgURLString: String, content: UNMutableNotificationContent) -> UNMutableNotificationContent{
        
        let myImageName = imgURLString.replacingOccurrences(of:"/", with:"-") // 変換
        let imagePath = getImagePath(imageName: myImageName)
        let fileManager = FileManager.default
        print(imagePath.path)
        //if fileManager.fileExists(atPath: imagePath.path) {
        //    print("FILE AVAILABLE")
        //} else {
        //    print("FILE NOT AVAILABLE")
            let result = imageLocalDownload(imgURLString: imgURLString, myImageName: myImageName)
        //    print(result)
        //}
        
        print(imagePath)
        guard let attachment = try? UNNotificationAttachment(identifier: "image", url: imagePath, options: nil) else { fatalError("fuck swift") }
        content.attachments = [attachment]
        return content
    }
    
    // MARK: - CLocationManagerDelegate
    
    //1分毎に通知を出力する
    @objc func sendPlaceAMinutes(){
        counter += 1
        sendNotification(type: "Timer", placeId: shufflePlaceList[counter].place_name)
    }
    
    //通知送る処理
    func sendNotification(type: String, placeId: String){
        // アクション設定
        let actionUseful = UNNotificationAction(identifier: "actionUseful",
                                            title: "へぇ",
                                            options: [.foreground])
        let actionUseless = UNNotificationAction(identifier: "actionUseless",
                                            title: "どうでもいい",
                                            options: [.foreground])

        let category = UNNotificationCategory(identifier: "category_select",
                                              actions: [actionUseful, actionUseless],
                                              intentIdentifiers: [],
                                              options: [])

        UNUserNotificationCenter.current().setNotificationCategories([category])
        let center = UNUserNotificationCenter.current()
        //UNUserNotificationCenter.current().delegate = self
        
        // UNMutableNotificationContent 作成
        var content = UNMutableNotificationContent()
        var imgURLString = ""
        
        for place in placeList{
            if place.place_name == placeId{
                content.title = "あなたは今 " + placeId + " にいますね？"
                content.subtitle = "ここで " + place.exhibit_name + " を思い出してください！"
                var split = place.kaisetsu.components(separatedBy: place.exhibit_iword)
                var kaisetsu = split[0]
                for i in 1..<(split.count){
                    kaisetsu += " \"" + place.exhibit_iword + "\" " + split[i]
                }
                
                split = place.review.components(separatedBy: place.place_iword)
                var rev = split[0]
                for i in 1..<(split.count){
                    rev += " \"" + place.place_iword + "\" " + split[i]
                }
                
                content.body = "なぜなら、展示物は「" + kaisetsu + "」と解説されていて、\nこの場所は「" + rev + " 」と評されていて関係があるんです"
                imgURLString = place.exhibit_image_url
                print(place.exhibit_iword)
            }
        }

        
        content.sound = UNNotificationSound.default
        // categoryIdentifierを設定
        content.categoryIdentifier = "category_select"
        // 画像を通知に付与
        if imgURLString != "" {
            content = appendImageToContents(imgURLString: imgURLString, content: content)
        }
        //content.attachments = [ attachment ]
        // 1秒後に発火する UNTimeIntervalNotificationTrigger 作成、
        let trigger = UNTimeIntervalNotificationTrigger.init(timeInterval: 1, repeats: false)

        // identifier, content, trigger から UNNotificationRequest 作成
        let request = UNNotificationRequest.init(identifier: "aSecondNotification", content: content, trigger: trigger)

        // UNUserNotificationCenter に request を追加
        center.add(request)
        
        //sendしたログの追記
        writeLog(content: "SendNotification", actionType: "", placeId: placeId, message: "")
    }
    
    // アクションを選択した際に呼び出されるメソッド
    //@available(iOS 10.0, *)
    /*
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: () -> Void) {
        print("in")
        // 選択されたアクションごとに処理を分岐
        switch response.actionIdentifier {
            
        case ActionIdentifier.actionUseful.rawValue:
            // 具体的な処理をここに記入
            // 変数oneをカウントアップしてラベルに表示
            one = one + 1
            countAct1.text = String(one)

        case ActionIdentifier.actionUseless.rawValue:
            // 具体的な処理をここに記入
            two = two + 1
            countAct2.text = String(two)

        default:
            ()
        }

        completionHandler()
    }
    */
    func countNotificationAction(response: UNNotificationResponse){
        
        print("receive response")
        
        switch response.actionIdentifier {
        case "actionUseful":
            actionUsefulCount += 1
            countAct1.text = actionUsefulCount.description
            writeLog(content: "receiveNotification", actionType: "Useful", placeId: response.notification.request.content.title, message: "")
            break
        case "actionUseless":
            actionUselessCount += 1
            countAct2.text = actionUselessCount.description
            writeLog(content: "receiveNotification", actionType: "Useless", placeId: response.notification.request.content.title, message: "")
            break
        default:    // アクションではなく通知自体をタップしたときは UNNotificationDefaultActionIdentifier が渡ってくる
            writeLog(content: "receiveNotification", actionType: "mistake", placeId: "", message: "")
            break
        }
    }

    // 位置情報取得認可
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            print("ユーザー認証未選択")
            locationManager.requestAlwaysAuthorization()
            break
        case .denied:
            print("ユーザーが位置情報取得を拒否しています。")
            //位置情報取得を促す処理を追記
            break
        case .restricted:
            print("位置情報サービスを利用できません")
            break
        case .authorizedWhenInUse:
            print("アプリケーション起動時のみ、位置情報の取得を許可されています。")
            break
        case .authorizedAlways:
            print("このアプリケーションは常時、位置情報の取得を許可されています。")
            break
        @unknown default:
            print("default")
        }
    }

    
    //json 出力
    func loadData() -> [PlaceInfo] {
        
        /// ①DocumentsフォルダURL取得
        guard let dirURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("フォルダURL取得エラー")
        }

        /// ②対象のファイルURL取得
        let fileURL = dirURL.appendingPathComponent("outputList.json")
        
        /// ③ファイルの読み込み
        guard let data = try? Data(contentsOf: fileURL) else {
            fatalError("ファイル読み込みエラー")
        }
        
        
        /*
        //①プロジェクト内にある"employees.json"ファイルのパス取得
        guard let url = Bundle.main.url(forResource: "outputList", withExtension: "json") else {
            fatalError("ファイルが見つからない")
        }
         
        /// ②employees.jsonの内容をData型プロパティに読み込み
        guard let data = try? Data(contentsOf: url) else {
            fatalError("ファイル読み込みエラー")
        }
        print(data.description)
        */
        /// ③JSONデコード処理
        let decoder = JSONDecoder()
        guard let placeInfos = try? decoder.decode([PlaceInfo].self, from: data) else {
            fatalError("JSON読み込みエラー")
        }
        
        /*
        /// ③ファイルの書き込み
        do {
            let text :String = String(data: data, encoding: .utf8)!
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            print(text)
        } catch {
            print("Error: \(error)")
        }
         */
        return placeInfos
    }
    


    // ジオフェンスモニタリング

    // モニタリング開始成功時に呼ばれる
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        print("モニタリング開始", region.identifier)
    }


    // モニタリングに失敗したときに呼ばれる
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("モニタリングに失敗しました。", error)
    }

    // ジオフェンス領域に侵入時に呼ばれる
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("設定したジオフェンスに入りました。")
        sendNotification(type: "Enter", placeId: String(region.identifier))
    }

    // ジオフェンス領域から出たときに呼ばれる
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("設定したジオフェンスから出ました。")
        sendNotification(type: "Exit", placeId: String(region.identifier))
    }

    // ジオフェンスの情報が取得できないときに呼ばれる
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("モニタリングエラーです。", error)
    }
    
    func writeLog(content: String, actionType: String, placeId: String, message: String){
        let logData = LogData(datetime: Date(), content: content, actionType: actionType, placeId: placeId, message: message)
       let encoder = JSONEncoder()
       encoder.dateEncodingStrategy = .iso8601
       encoder.outputFormatting = .prettyPrinted
       
       do {
           let data = try encoder.encode(logData)
           let jsonstr = String(data: data, encoding: .utf8)!
           print(jsonstr)
           
           let dir = FileManager.default.urls(
               for: .documentDirectory,
               in: .userDomainMask
           ).first!
           let fileUrl = dir.appendingPathComponent(logFileName)
           if !FileManager.default.fileExists(atPath: fileUrl.path) {
             // ファイルが存在しない場合の処理
               // 新規ファイルを作成する
               createAndWriteTextFile()
           }
           
           appendText(fileURL: fileUrl, string: jsonstr)

       } catch {
           print(error.localizedDescription)
       }
    }
    
    func appendText(fileURL: URL, string: String) {
         
        do {
            let fileHandle = try FileHandle(forWritingTo: fileURL)
             
            // 区切りを入れる
            let stringToWrite = string+","
             
            // ファイルの最後に追記
            fileHandle.seekToEndOfFile()
            fileHandle.write(stringToWrite.data(using: String.Encoding.utf8)!)
         
        } catch let error as NSError {
            print("failed to append: \(error)")
        }
    }
    
    func createAndWriteTextFile() {
         
        // 作成するテキストファイルの名前
        let initialText = ""
         
        // DocumentディレクトリのfileURLを取得
        if let documentDirectoryFileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last {
         
            // ディレクトリのパスにファイル名をつなげてファイルのフルパスを作る
            let targetTextFilePath = documentDirectoryFileURL.appendingPathComponent(logFileName)
             
            print("書き込むファイルのパス: \(targetTextFilePath)")
             
            do {
                try initialText.write(to: targetTextFilePath, atomically: true, encoding: String.Encoding.utf8)
            } catch let error as NSError {
                print("failed to write: \(error)")
            }
        }
    }
    
    
}

extension Array where Element: Equatable {
    typealias E = Element

    func subtracting(_ other: [E]) -> [E] {
        return self.compactMap { element in
            if (other.filter { $0 == element }).count == 0 {
                return element
            } else {
                return nil
            }
        }
    }

    mutating func subtract(_ other: [E]) {
        self = subtracting(other)
    }
}
