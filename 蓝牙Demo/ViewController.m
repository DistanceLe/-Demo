//
//  ViewController.m
//  蓝牙Demo
//
//  Created by LiJie on 16/2/22.
//  Copyright © 2016年 LiJie. All rights reserved.
//

#import "ViewController.h"

#import <CoreBluetooth/CoreBluetooth.h>

#define kPeripheralName @"Lijie's Device" //外围设备名称
#define kServiceUUID @"C4FB2349-72FE-4CA2-94D6-1F3CB16331EE" //服务的UUID
#define kCharacteristicUUID @"6A3E4B28-522D-4B3B-82A9-D5E2004534FC" //特征的UUID


/**  
 CBPeripheralManager：外围设备  通常用于发布服务、生成数据、保存数据。外围设备发布并广播服务，告诉周围的中央设备它的可用服务和特征。
 CBCentralManager：中央设备  使用外围设备的数据。中央设备扫描到外围设备后会就会试图建立连接，一旦连接成功就可以使用这些服务和特征。
 
 外围设备和中央设备之间交互的桥梁是服务(CBService)和特征(CBCharacteristic)，二者都有一个唯一的标识UUID（CBUUID类型）来唯一确定一个服务或者特征，每个服务可以拥有多个特征
 */



/**  创建一个外围设备通常分为以下几个步骤：
 
 1.创建外围设备CBPeripheralManager对象并指定代理。
 2.创建特征CBCharacteristic、服务CBSerivce并添加到外围设备
 3.外围设备开始广播服务（startAdvertisting:）。
 4.和中央设备CBCentral进行交互。 */


/**  中央设备的创建一般可以分为如下几个步骤：
 
 1.创建中央设备管理对象CBCentralManager并指定代理。
 2.扫描外围设备，一般发现可用外围设备则连接并保存外围设备。
 3.查找外围设备服务和特征，查找到可用特征则读取特征数据。 */


/**  
 ATT，即Attribute Protocol，用于发现、读、写对端设备的协议(针对BLE设备)
 RSSI：信号强弱值，防丢器会用到。
 UUID：唯一标识符，用于区分设备 是一个128-bit值 （16位字节）
 service UUID：服务，一个 Server 会包含多个characteristic，用 UUID 来区分。
 characteristic：特征，用 UUID 来区分 */

/**     注意点：
 1. updateValue:ForCharacteristic:OnSubscribedCentrals: 是有返回值得。
    如果此时蓝牙的缓存满了，或者处理更新的队列满了，那么这次更新请求就会被丢弃
 2. CBCharacteristic不支持mutableCopy。 
 3. 不要往同一个peripheral manager中重复添加同一个服务，否则会出错。
    中心设备可能接收不到更新提醒，还没有任何错误提示。
 
 4. BLE 4.0中规定，不会在设备之间建立长连接，而是启动了定时器，每隔一段时间，进行一次连接，连接持续时间只是一瞬间。
    发起连接的动作是由中心设备完成的，当调用了central的connectToPeripheral:方法后，这个定时连接的过程就开始了。
    中心设备每隔一段时间（在iPhone 5c上测试是一秒多）与目标远端设备连接一次
    每一次连接瞬间的发生，都会触发didConnectPeripheral:代理方法
 
 5. 如果对特征值进行的订阅，在不需要的时候最好尽快取消订阅，这样为远端设备省电
 6. 在对特征值进行读写或订阅操作之前，需要先知道这个特征是否支持和允许这些操作
 */

@interface ViewController ()<CBPeripheralManagerDelegate, CBCentralManagerDelegate, CBPeripheralDelegate>

@property(nonatomic, assign)BOOL isCentral;

@property(nonatomic, strong)CBPeripheralManager* peripheralManager;//外围设备管理器
@property(nonatomic, strong)NSMutableArray* centralArray;//订阅此外围设备特征的中心设备
@property(nonatomic, strong)CBMutableCharacteristic* characteristicM;//特征
@property (weak, nonatomic) IBOutlet UITextView *logInfo;

/**  中心服务器 */
@property(nonatomic, strong)CBCentralManager* centralManager;//中心设备管理器
@property(nonatomic, strong)NSMutableArray* peripherals;//连接的外围设备


@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title=@"外围设备";
    [self ininData];
}

-(void)ininData
{
    self.centralArray=[NSMutableArray array];
    self.peripherals=[NSMutableArray array];
}

#pragma mark - ================ UI事件 ==================
- (IBAction)sort:(UIBarButtonItem *)sender
{
    _isCentral=!_isCentral;
    if (_isCentral) {
        [self.peripheralManager stopAdvertising];
        [self.peripheralManager removeAllServices];
        self.title=@"中心服务器";
    }
    else
    {
        [self.centralManager stopScan];
        
        self.title=@"外围设备";
    }
}

//创建外围设备
- (IBAction)left:(UIBarButtonItem *)sender
{
    if (_isCentral) {
        
        //创建中心设备管理器并设置当前控制器视图为代理
        _centralManager=[[CBCentralManager alloc]initWithDelegate:self queue:nil];
        return;
    }
    _peripheralManager=[[CBPeripheralManager alloc]initWithDelegate:self queue:nil];
}
//更新数据
- (IBAction)right:(UIBarButtonItem *)sender
{
    if (_isCentral) {
        return;
    }
    [self updateCharacteristicValue];
}

#pragma mark - ================ 外围代理 ==================
/**  外围设备状态发生变化后调用 */
-(void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral
{
    switch (peripheral.state) {
        case CBPeripheralManagerStatePoweredOn:
            NSLog(@"BLE已打开");
            [self writeToLog:@"BLE已打开"];
            //添加服务
            [self setupService];
            break;
            
        default:
            NSLog(@"此设备不支持BLE或未打开蓝牙功能，无法作为外围设备.");
            [self writeToLog:@"此设备不支持BLE或未打开蓝牙功能，无法作为外围设备."];
            break;
    }
}

/**  外围设备添加服务后调用 */
-(void)peripheralManager:(CBPeripheralManager *)peripheral didAddService:(CBService *)service error:(NSError *)error
{
    if (error) {
        NSLog(@"向外围设备添加服务失败，错误详情：%@",error.localizedDescription);
        [self writeToLog:[NSString stringWithFormat:@"向外围设备添加服务失败，错误详情：%@",error.localizedDescription]];
        return;
    }
    
    //添加服务后开始广播
    NSDictionary* dic=@{CBAdvertisementDataLocalNameKey:kPeripheralName};//广播设置
    [self.peripheralManager startAdvertising:dic];
    NSLog(@"向外围设备添加了服务并开始广播...");
    [self writeToLog:@"向外围设备添加了服务并开始广播..."];
}

/**  开始广播 */
-(void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral error:(NSError *)error
{
    if (error) {
        NSLog(@"启动广播过程中发生错误，错误信息%@",error.localizedDescription);
        [self writeToLog:[NSString stringWithFormat:@"启动广播过程中发生错误，错误信息：%@",error.localizedDescription]];
        return;
    }
    NSLog(@"启动广播。。。。");
    [self writeToLog:@"启动广播。。。"];
}

/**  外围设备的特征 被中心设备订阅后： */
-(void)peripheralManager:(CBPeripheralManager *)peripheral central:(CBCentral *)central didSubscribeToCharacteristic:(CBCharacteristic *)characteristic
{
    NSLog(@"中心设备：%@已订阅特征：%@",central, characteristic);
    [self writeToLog:[NSString stringWithFormat:@"中心设备：%@ 已订阅特征：%@.",central.identifier.UUIDString,characteristic.UUID]];
    
    //发现中心设备并存储
    if (![self.centralArray containsObject:central]) {
        [self.centralArray addObject:central];
    }
    /*中心设备订阅成功后外围设备可以更新特征值发送到中心设备,一旦更新特征值将会触发中心设备的代理方法：
     -(void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
     */
    
//    [self updateCharacteristicValue];
}

/**  取消订阅特征 */
-(void)peripheralManager:(CBPeripheralManager *)peripheral central:(CBCentral *)central didUnsubscribeFromCharacteristic:(CBCharacteristic *)characteristic
{
    NSLog(@"didUnsubscribeFromCharacteristic");
}

/**  收到 中心设备发送来的读请求 */
-(void)peripheralManager:(CBPeripheralManager *)peripheral didReceiveReadRequest:(CBATTRequest *)request
{
    NSLog(@"收到读characteristics请求");
    [self writeToLog:@"收到读characteristics请求"];
}

/**  收到 中心设备发送来的写请求 */
-(void)peripheralManager:(CBPeripheralManager *)peripheral didReceiveWriteRequests:(NSArray<CBATTRequest *> *)requests
{
    NSLog(@"收到写characteristics请求");
    [self writeToLog:@"收到写characteristics请求"];
}

/**  外设 还原状态 */
-(void)peripheralManager:(CBPeripheralManager *)peripheral willRestoreState:(NSDictionary<NSString *,id> *)dict
{
    NSLog(@"willRestoreState");
}


#pragma mark - ================ 中心代理 ==================
-(void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    switch (central.state) {
        case CBPeripheralManagerStatePoweredOn:
            NSLog(@"BLE已打开. 开始 扫描外围设备");
            [self writeToLog:@"BLE已打开. 开始 扫描外围设备"];
            //蓝牙打开： 开始 扫描外围设备
            
            //这个参数应该也是可以指定特定的peripheral的UUID,那么理论上这个central只会discover这个特定的设备，但是我实际测试发现，如果用特定的UUID传参根本找不到任何设备
//            [central scanForPeripheralsWithServices:@[[CBUUID UUIDWithString:kServiceUUID]] options:@{CBCentralManagerScanOptionAllowDuplicatesKey:@YES}];
            [central scanForPeripheralsWithServices:nil options:@{CBCentralManagerScanOptionAllowDuplicatesKey:@YES}];
            break;
            
        default:
            NSLog(@"此设备不支持BLE或未打开蓝牙功能，无法作为外围设备.");
            [self writeToLog:@"此设备不支持BLE或未打开蓝牙功能，无法作为外围设备."];
            break;
    }
}

/**
 *  发现外围设备
 *
 *  @param central           中心设备
 *  @param peripheral        外围设备
 *  @param advertisementData 收到的广播数据
 *  @param RSSI              信号质量（信号强度）
 */
-(void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *,id> *)advertisementData RSSI:(NSNumber *)RSSI
{
    NSLog(@"发现外围设备...  停止扫描 ");
    [self writeToLog:[NSString stringWithFormat:@"发现外围设备.%@..  停止扫描",advertisementData[CBAdvertisementDataLocalNameKey]]];
    //停止扫描
    [self.centralManager stopScan];
    //连接外围设备
    if (peripheral) {
        //添加保存外围设备，注意如果这里不保存外围设备（或者说peripheral没有一个强引用，无法到达连接成功（或失败）的代理方法，因为在此方法调用完就会被销毁
        if (![self.peripherals containsObject:peripheral]) {
            [self.peripherals addObject:peripheral];
        }
        NSLog(@"开始连接外围设备...");
        [self writeToLog:@"开始连接外围设备..."];
        [self.centralManager connectPeripheral:peripheral options:nil];
    }
}
/**  连接到外围设备 */
-(void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    NSLog(@"连接外围设备成功!");
    [self writeToLog:@"连接外围设备成功!"];
    //设置外围设备的代理为当前视图控制器
    peripheral.delegate=self;
    //外围设备开始寻找服务
    [peripheral discoverServices:@[[CBUUID UUIDWithString:kServiceUUID]]];
}

/**  连接外围设备失败 */
-(void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    NSLog(@"连接外围设备失败!");
    [self writeToLog:@"连接外围设备失败!"];
}

#pragma mark - ================ CBPeripheral 代理方法 ==================
/**  中心设备获取到外设的 services：后 */
-(void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    NSLog(@"CBPeripheral 代理方法 ===已发现可用服务...");
    [self writeToLog:@"CBPeripheral 代理方法 ===已发现可用服务..."];
    if (error) {
        NSLog(@"CBPeripheral 代理方法 ===外围设备寻找服务过程中发生错误，错误信息：%@",error.localizedDescription);
        [self writeToLog:[NSString stringWithFormat:@"CBPeripheral 代理方法 ===外围设备寻找服务过程中发生错误，错误信息：%@",error.localizedDescription]];
    }
    
    //遍历查找到的服务
    CBUUID* serviceUUID=[CBUUID UUIDWithString:kServiceUUID];
    CBUUID* characteristicUUID=[CBUUID UUIDWithString:kCharacteristicUUID];
    for (CBService* service in peripheral.services) {
        if ([service.UUID isEqual:serviceUUID]) {
            //获取外设服务中的  特征
            [peripheral discoverCharacteristics:@[characteristicUUID] forService:service];
        }
    }
}
/**  获取到外部设备 的特征（Characteristics）后：  */
-(void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    NSLog(@"CBPeripheral 代理方法 ===已发现可用特征...");
    [self writeToLog:@"CBPeripheral 代理方法 ===已发现可用特征..."];
    if (error) {
        NSLog(@"CBPeripheral 代理方法 ===外围设备寻找特征过程中发生错误，错误信息：%@",error.localizedDescription);
        [self writeToLog:[NSString stringWithFormat:@"CBPeripheral 代理方法 ===外围设备寻找特征过程中发生错误，错误信息：%@",error.localizedDescription]];
    }
    //遍历服务中的特征
    CBUUID* serviceUUID=[CBUUID UUIDWithString:kServiceUUID];
    CBUUID* characteristicUUID=[CBUUID UUIDWithString:kCharacteristicUUID];
    if ([service.UUID isEqual:serviceUUID]) {
        for (CBCharacteristic* characteristic in service.characteristics) {
            if ([characteristic.UUID isEqual:characteristicUUID]) {
                //情景一：通知
                /*找到特征后设置外围设备为已通知状态（订阅特征）：
                 *1.调用此方法会触发代理方法：-(void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
                 *2.调用此方法会触发外围设备的订阅代理方法
                 */
                [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                //情景二：读取 （获取外设的Characteristics 的 Descriptor 和 Descriptor 的值：）
//                [peripheral readValueForCharacteristic:characteristic];
//                    if(characteristic.value){
//                    NSString *value=[[NSString alloc]initWithData:characteristic.value encoding:NSUTF8StringEncoding];
//                    NSLog(@"读取到特征值：%@",value);
//                }

            }
        }
    }
}

/**  收到外设特征更新的 通知 */
-(void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    NSLog(@"CBPeripheral 代理方法 ===收到特征更新通知...");
    [self writeToLog:@"CBPeripheral 代理方法 ===收到特征更新通知..."];
    if (error) {
        NSLog(@"CBPeripheral 代理方法 ===更新通知状态时发生错误，错误信息：%@",error.localizedDescription);
    }
    //给特征值设置新的值
    CBUUID* characteristicUUID=[CBUUID UUIDWithString:kCharacteristicUUID];
    if ([characteristic.UUID isEqual:characteristicUUID]) {
        if (characteristic.isNotifying) {
            if (characteristic.properties==CBCharacteristicPropertyNotify) {
                NSLog(@"CBPeripheral 代理方法 ===已订阅特征通知.");
                [self writeToLog:@"CBPeripheral 代理方法 ===已订阅特征通知."];
                return;
            }
            else if (characteristic.properties==CBCharacteristicPropertyRead)
            {
                //从外围设备读取新值,调用此方法会触发代理方法：-(void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
                [peripheral readValueForCharacteristic:characteristic];
            }
            else
            {
                NSLog(@"CBPeripheral 代理方法 ===停止已停止.");
                [self writeToLog:@"CBPeripheral 代理方法 ===停止已停止."];
                //取消连接
                [self.centralManager cancelPeripheralConnection:peripheral];
            }
        }
    }
}

/**  更新特征值后（调用readValueForCharacteristic:方法或者外围设备在订阅后更新特征值都会调用此代理方法） */
-(void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error) {
        NSLog(@"CBPeripheral 代理方法 ===更新特征值时发生错误，错误信息：%@",error.localizedDescription);
        [self writeToLog:[NSString stringWithFormat:@"CBPeripheral 代理方法 ===更新特征值时发生错误，错误信息：%@",error.localizedDescription]];
        return;
    }
    if (characteristic.value) {
        //搜索 特征描述 会调用didDiscoverDescriptorsForCharacteristic
//        [peripheral discoverDescriptorsForCharacteristic:characteristic];
        
        
        NSString* value=[[NSString alloc]initWithData:characteristic.value encoding:NSUTF8StringEncoding];
        NSLog(@"CBPeripheral 代理方法 ===读取到特征值：%@",value);
        [self writeToLog:[NSString stringWithFormat:@"CBPeripheral 代理方法 ===读取到特征值：%@",value]];
    }
    else
    {
        NSLog(@"CBPeripheral 代理方法 ===未发现特征值.");
        [self writeToLog:@"CBPeripheral 代理方法 ===未发现特征值."];
    }
}

/**  搜索到该描述的特征后 调用 */
-(void)peripheral:(CBPeripheral *)peripheral didDiscoverDescriptorsForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error{
    
}

/**  获取到Descriptors 的值   Descriptors 是对 characteristic 的描述，一般是字符串*/
-(void)peripheral:(CBPeripheral *)peripheral didUpdateValueForDescriptor:(CBDescriptor *)descriptor error:(NSError *)error{
    
}

#pragma mark - ================ Action ==================
//更新特征值
-(void)updateCharacteristicValue
{
    //特征值
    NSString* valueStr=[NSString stringWithFormat:@"%@ --%@",kSecPolicyName, [NSDate date]];
    NSData* value=[valueStr dataUsingEncoding:NSUTF8StringEncoding];
    //更新特征值 是有返回值得。。
    BOOL isSend = [self.peripheralManager updateValue:value forCharacteristic:self.characteristicM onSubscribedCentrals:nil];
    if (isSend) {
        [self writeToLog:[NSString stringWithFormat:@"更新特征值：%@",valueStr]];
    }else{
        [self writeToLog:[NSString stringWithFormat:@"更新特征值：%@ 失败😔",valueStr]];
    }
    
    
}

/**  中心设备 向外围 写特征值(或描述) */
-(void)writeCharacteristic{
    CBPeripheral* peripheral = self.peripherals.firstObject;
    if (peripheral) {
//        peripheral writeValue:(nonnull NSData *) forDescriptor:(nonnull CBDescriptor *)
//        peripheral writeValue:(nonnull NSData *) forCharacteristic:(nonnull CBCharacteristic *) type:(CBCharacteristicWriteType)
    }
}

/**  初始化 外设的服务和特征 */
-(void)setupService
{
    /*1.创建特征*/
    //创建特征的UUID对象
    CBUUID* characteristicUUID=[CBUUID UUIDWithString:kCharacteristicUUID];
    //特征值
//    NSString *valueStr=kPeripheralName;
//    NSData *value=[valueStr dataUsingEncoding:NSUTF8StringEncoding];
    //创建特征
    /** 参数
     * uuid:特征标识
     * properties:特征的属性，例如：可通知、可写、可读等
     * value:特征值
     * permissions:特征的权限
     */
    
    CBMutableCharacteristic* charateristicM=[[CBMutableCharacteristic alloc]initWithType:characteristicUUID properties:CBCharacteristicPropertyNotify value:nil permissions:CBAttributePermissionsReadable];
    self.characteristicM=charateristicM;
    //    CBMutableCharacteristic *characteristicM=[[CBMutableCharacteristic alloc]initWithType:characteristicUUID properties:CBCharacteristicPropertyRead value:nil permissions:CBAttributePermissionsReadable];
    //    characteristicM.value=value;
    
    /*创建服务并且设置特征*/
    //创建服务UUID对象
    CBUUID* serviceUUID=[CBUUID UUIDWithString:kServiceUUID];
    //创建服务
    CBMutableService* serviceM=[[CBMutableService alloc]initWithType:serviceUUID primary:YES];
    //设置服务的特征
    [serviceM setCharacteristics:@[charateristicM]];
    
    /**  将服务添加到外围设备 */
    [self.peripheralManager addService:serviceM];
}

/**  写入到 页面的log */
-(void)writeToLog:(NSString*)info
{
    self.logInfo.text=[NSString stringWithFormat:@"%@\n%@",self.logInfo.text, info];
}











@end
