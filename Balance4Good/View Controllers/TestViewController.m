//
//  TestViewController.m
//  Balance4Good
//
//  Created by Hira Daud on 11/18/14.
//  Copyright (c) 2014 Hira Daud. All rights reserved.
//

#import "TestViewController.h"
#import "BLEUtility.h"
#import "TestDetails.h"
#import "WelcomeViewController.h"
#import <AWSiOSSDKv2/AWSCore.h>
#import <AWSiOSSDKv2/S3.h>
#import "Constants.h"

#define ERROR_ALERT 1
#define SUCCESS_ALERT 2

@interface TestViewController ()

@end

@implementation TestViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    [self initialize];

    //Start the logTimer and countUpTimer. LogTimer is used for logging values while countUp is used to show the elapsed Timed
    //In case of logTimer, if the sensors are not giving values yet(may take a few milliseconds), the data is not logged
    
    self.logTimer = [NSTimer scheduledTimerWithTimeInterval:(float)self.updateInterval/1000.0f target:self selector:@selector(logValues:) userInfo:nil repeats:YES];
    
    self.countUpTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateTimer) userInfo:nil repeats:YES];
    
    [self.navigationItem setHidesBackButton:YES animated:NO];

}

-(void)cancel:(BOOL)goBack
{
    //if logTimer is running, invalidate it and set it to null
    if(self.logTimer)
    {
        [self.logTimer invalidate];
        self.logTimer = nil;
    }
    
    //if countUpTimer is running, invalidate it and set it to null
    if(self.countUpTimer)
    {
        [self.countUpTimer invalidate];
        self.countUpTimer = nil;
    }

    UIViewController *vc = nil;
    
    for(vc in self.navigationController.viewControllers)
    {
        if([vc isKindOfClass:[WelcomeViewController class]])
            break;
    }
    
    [[self.devices manager] stopScan];
    
    if(goBack)
        [self.navigationController popToViewController:vc animated:YES];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    self.sensorsEnabled = [[NSMutableArray alloc] init];


    BOOL testConnected = NO;
    
    //Check every peripheral (sensorTag). if it is not connected, connect & configure it and then start getting values.
    // If it is alreayd connected, just configure it and start getting values
    for(CBPeripheral *peripheral in self.devices.peripherals)
    {
        if (![peripheral isConnected])
        {
            self.devices.manager.delegate = self;
            [self.devices.manager connectPeripheral:peripheral options:nil];
        }
        else
        {
            testConnected = YES;
            peripheral.delegate = self;
            [self configureSensorTag:peripheral];
        }
    }
    
}

//De-configure all the sensors (so that it stops broadcasting values)

-(void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    for(CBPeripheral *peripheral in self.devices.peripherals)
        [self deconfigureSensorTag:peripheral];
}

-(void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    self.sensorsEnabled = nil;
    self.devices.manager.delegate = nil;
    self.gyroSensors = nil;
    
    self.current_Values = nil;
    
}


-(void)initialize
{
    [self initGyroSensors];
    
    //retreive update rate from Technical Configuration.
    
    self.updateInterval = [[[NSUserDefaults standardUserDefaults] objectForKey:@"updateRate"] intValue];  //(in milliseconds) minimum update interval for both gyro and accelero
    
    
    //Initialize all the values. Not that much necessary but still done as a pre-caution
    
    self.current_Values = [NSMutableDictionary dictionaryWithCapacity:13];
    [self.current_Values setObject:@"" forKey:@"timestamp"];
    [self.current_Values setObject:@"" forKey:@"S1_AX"];
    [self.current_Values setObject:@"" forKey:@"S1_AY"];
    [self.current_Values setObject:@"" forKey:@"S1_AZ"];
    [self.current_Values setObject:@"" forKey:@"S1_GX"];
    [self.current_Values setObject:@"" forKey:@"S1_GY"];
    [self.current_Values setObject:@"" forKey:@"S1_GZ"];
    [self.current_Values setObject:@"" forKey:@"S2_AX"];
    [self.current_Values setObject:@"" forKey:@"S2_AY"];
    [self.current_Values setObject:@"" forKey:@"S2_AZ"];
    [self.current_Values setObject:@"" forKey:@"S2_GX"];
    [self.current_Values setObject:@"" forKey:@"S2_GY"];
    [self.current_Values setObject:@"" forKey:@"S2_GZ"];

}


#pragma mark - Sensor Configuration
//Initialize all the gyro sensors
-(void)initGyroSensors
{
    self.gyroSensors = [NSMutableArray array];
    for(int i=0;i<self.devices.peripherals.count;i++)
    {
        sensorIMU3000 *gyroSensor = [[sensorIMU3000 alloc] init];
        [self.gyroSensors addObject:gyroSensor];
    }
}

-(void) configureSensorTag:(CBPeripheral*)peripheral
{
    // Configure sensortag, turning on Sensors and setting update period for sensors etc ...
    
    if ([self sensorEnabled:@"Accelerometer active"])
    {
        CBUUID *sUUID = [CBUUID UUIDWithString:[self.devices.setupData valueForKey:@"Accelerometer service UUID"]];
        CBUUID *cUUID = [CBUUID UUIDWithString:[self.devices.setupData valueForKey:@"Accelerometer config UUID"]];
        CBUUID *pUUID = [CBUUID UUIDWithString:[self.devices.setupData valueForKey:@"Accelerometer period UUID"]];

        uint8_t periodData = (uint8_t)(self.updateInterval / 10);
        NSLog(@"%d",periodData);
        
        [BLEUtility writeCharacteristic:peripheral sCBUUID:sUUID cCBUUID:pUUID data:[NSData dataWithBytes:&periodData length:1]];
        
        uint8_t data = 0x01;
        [BLEUtility writeCharacteristic:peripheral sCBUUID:sUUID cCBUUID:cUUID data:[NSData dataWithBytes:&data length:1]];
        cUUID = [CBUUID UUIDWithString:[self.devices.setupData valueForKey:@"Accelerometer data UUID"]];
        [BLEUtility setNotificationForCharacteristic:peripheral sCBUUID:sUUID cCBUUID:cUUID enable:YES];
        [self.sensorsEnabled addObject:@"Accelerometer"];
    }
    
    if ([self sensorEnabled:@"Gyroscope active"])
    {
        CBUUID *sUUID =  [CBUUID UUIDWithString:[self.devices.setupData valueForKey:@"Gyroscope service UUID"]];
        CBUUID *cUUID =  [CBUUID UUIDWithString:[self.devices.setupData valueForKey:@"Gyroscope config UUID"]];
        CBUUID *pUUID = [CBUUID UUIDWithString:[self.devices.setupData valueForKey:@"Gyroscope period UUID"]];
        
        uint8_t periodData = (uint8_t)(self.updateInterval / 10);
        NSLog(@"%d",periodData);

        [BLEUtility writeCharacteristic:peripheral sCBUUID:sUUID cCBUUID:pUUID data:[NSData dataWithBytes:&periodData length:1]];

        uint8_t data = 0x07;
        [BLEUtility writeCharacteristic:peripheral sCBUUID:sUUID cCBUUID:cUUID data:[NSData dataWithBytes:&data length:1]];
        cUUID =  [CBUUID UUIDWithString:[self.devices.setupData valueForKey:@"Gyroscope data UUID"]];
        [BLEUtility setNotificationForCharacteristic:peripheral sCBUUID:sUUID cCBUUID:cUUID enable:YES];
        [self.sensorsEnabled addObject:@"Gyroscope"];
    }
}

-(void) deconfigureSensorTag:(CBPeripheral*)peripheral
{
    //Check if sensor is enabled. If Yes, then configure it else dont.

    if ([self sensorEnabled:@"Accelerometer active"])
    {
        CBUUID *sUUID =  [CBUUID UUIDWithString:[self.devices.setupData valueForKey:@"Accelerometer service UUID"]];
        CBUUID *cUUID =  [CBUUID UUIDWithString:[self.devices.setupData valueForKey:@"Accelerometer config UUID"]];
        uint8_t data = 0x00;
        [BLEUtility writeCharacteristic:peripheral sCBUUID:sUUID cCBUUID:cUUID data:[NSData dataWithBytes:&data length:1]];
        cUUID =  [CBUUID UUIDWithString:[self.devices.setupData valueForKey:@"Accelerometer data UUID"]];
        [BLEUtility setNotificationForCharacteristic:peripheral sCBUUID:sUUID cCBUUID:cUUID enable:NO];
    }
    if ([self sensorEnabled:@"Gyroscope active"])
    {
        CBUUID *sUUID =  [CBUUID UUIDWithString:[self.devices.setupData valueForKey:@"Gyroscope service UUID"]];
        CBUUID *cUUID =  [CBUUID UUIDWithString:[self.devices.setupData valueForKey:@"Gyroscope config UUID"]];
        uint8_t data = 0x00;
        [BLEUtility writeCharacteristic:peripheral sCBUUID:sUUID cCBUUID:cUUID data:[NSData dataWithBytes:&data length:1]];
        cUUID =  [CBUUID UUIDWithString:[self.devices.setupData valueForKey:@"Gyroscope data UUID"]];
        [BLEUtility setNotificationForCharacteristic:peripheral sCBUUID:sUUID cCBUUID:cUUID enable:NO];
    }
}
-(bool)sensorEnabled:(NSString *)Sensor
{
    NSString *val = [self.devices.setupData valueForKey:Sensor];
    if (val)
    {
        if ([val isEqualToString:@"1"]) return TRUE;
    }
    return FALSE;
}

-(int)sensorPeriod:(NSString *)Sensor
{
    NSString *val = [self.devices.setupData valueForKey:Sensor];
    return [val intValue];
}

#pragma mark - CBCentralManager Delegate
-(void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    
}

-(void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    peripheral.delegate = self;
    [peripheral discoverServices:nil];
}

#pragma mark - CBPeripheral Delegate
//All these functions are discussed in StartTestViewController.m
-(void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    if([service.UUID isEqual:[CBUUID UUIDWithString:[self.devices.setupData valueForKey:@"Gyroscope service UUID"]]])
    {
        [self configureSensorTag:peripheral];
        
//        if(!self.logTimer)
//        {
//            self.logTimer = [NSTimer scheduledTimerWithTimeInterval:(float)self.updateInterval/1000.0f target:self selector:@selector(logValues:) userInfo:nil repeats:YES];
//            self.countUpTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateTimer) userInfo:nil repeats:YES];
//        }
    }
}

-(void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    for(CBService *service in peripheral.services)
        [peripheral discoverCharacteristics:nil forService:service];
}

-(void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    NSLog(@"didUpdateNotificationStateForCharacteristic %@, error = %@",characteristic.UUID,error);
}

-(void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    
    //Check if the data is being broadcast by accelerometer sensor. If Yes, read its values and store it
    
    if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:[self.devices.setupData valueForKey:@"Accelerometer data UUID"]]])
    {
        int deviceIndex = [self getDeviceIndex:peripheral];

        float x = [sensorKXTJ9 calcXValue:characteristic.value];
        float y = [sensorKXTJ9 calcYValue:characteristic.value];
        float z = [sensorKXTJ9 calcZValue:characteristic.value];

        [self.current_Values setObject:[NSString stringWithFormat:@"%0.3f",x] forKey:[NSString stringWithFormat:@"S%d_AX",deviceIndex+1]];
        [self.current_Values setObject:[NSString stringWithFormat:@"%0.3f",y] forKey:[NSString stringWithFormat:@"S%d_AY",deviceIndex+1]];
        [self.current_Values setObject:[NSString stringWithFormat:@"%0.3f",z] forKey:[NSString stringWithFormat:@"S%d_AZ",deviceIndex+1]];
    }
    
    //Check if the data is being broadcast by gyroscope sensor. If Yes, read its values and store it
    if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:[self.devices.setupData valueForKey:@"Gyroscope data UUID"]]])
    {
        int deviceIndex = [self getDeviceIndex:peripheral];
        sensorIMU3000 *gyroSensor;
    
        gyroSensor = [self.gyroSensors objectAtIndex:deviceIndex];
        
        float x = [gyroSensor calcXValue:characteristic.value];
        float y = [gyroSensor calcYValue:characteristic.value];
        float z = [gyroSensor calcZValue:characteristic.value];
        

        [self.current_Values setObject:[NSString stringWithFormat:@"%0.3f",x] forKey:[NSString stringWithFormat:@"S%d_GX",deviceIndex+1]];
        [self.current_Values setObject:[NSString stringWithFormat:@"%0.3f",y] forKey:[NSString stringWithFormat:@"S%d_GY",deviceIndex+1]];
        [self.current_Values setObject:[NSString stringWithFormat:@"%0.3f",z] forKey:[NSString stringWithFormat:@"S%d_GZ",deviceIndex+1]];

    }
}


-(void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    NSLog(@"didWriteValueForCharacteristic %@ error = %@",characteristic.UUID,error);
}

-(int)getDeviceIndex:(CBPeripheral*)peripheral
{
    for(int i=0;i<self.devices.peripherals.count;i++)
    {
        CBPeripheral *peri = [self.devices.peripherals objectAtIndex:i];
        if([peripheral isEqual:peri])
            return i;
    }
    return -1;
}

- (IBAction) handleCalibrateGyro
{
    NSLog(@"Calibrate gyroscope pressed ! ");
    for(sensorIMU3000 *gyroSensor in self.gyroSensors)
        [gyroSensor calibrate];
    
}

- (IBAction)save:(UIButton *)sender
{
    if([[[TestDetails sharedInstance] dataPoints] count] == 0)
    {
        //sender is nil when time is up. So when time is up, don't save data, end test and go back to previous screen.
        if(!sender)
            [self cancel:YES];
        else
        {
            //sender is not nil when save is pressed. In that case, dont end test. Just show message "No Data To Save".
            
            [[[UIAlertView alloc] initWithTitle:@"Balance4Good" message:@"No Data To Save" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles: nil] show];
        }
        return;
    }
    // In case we have data points, first call endTest to store all data and create its JSON
    // then deconfigure the peripheral
    // and final store the file to the Saved_Data Folder
    // finally show the Test Complete View Controller
    NSString *data = [[TestDetails sharedInstance] endTest];
    
    for(CBPeripheral *peripheral in self.devices.peripherals)
        [self deconfigureSensorTag:peripheral];
    
    
    NSString *Data_Folder = [[TestDetails sharedInstance] getDataFolderPath];
    
    NSLog(@"test_id:%@",[[TestDetails sharedInstance] test_id]);
    
    NSString *fileName = [@"b4g-" stringByAppendingFormat:@"%@.json",[[TestDetails sharedInstance] test_id]];    //test_id is stored at index 1
    NSURL *fileURL = [NSURL fileURLWithPath:[Data_Folder stringByAppendingPathComponent:fileName]];
    
    [data writeToURL:fileURL atomically:YES encoding:NSUTF8StringEncoding error:nil];

    [self cancel:NO];

    [self performSegueWithIdentifier:@"showTestCompleteVC" sender:nil];
    
}

- (IBAction)cancelTest:(UIButton *)sender
{
    [self cancel:YES];
}


#pragma mark - Log Values
-(void) logValues:(NSTimer*)timer
{
    NSMutableDictionary *vals = [NSMutableDictionary dictionaryWithDictionary:self.current_Values];

    
    BOOL dataExists = [self dataExists:vals];
    
    //If data does not exists & there are no data points already,don't log data.
    if([[[TestDetails sharedInstance] dataPoints] count] == 0 && !dataExists)
        return;
    
    //Just a redundant check for <50ms data as sometimes we just get only timestamp logged.
    if([vals count] == 0)
        return;
    
    //add timestamp
    [vals setObject:[[TestDetails sharedInstance] getFormattedTimestamp:YES] forKey:@"timestamp"];

    //add the data point to the data points array
    [[[TestDetails sharedInstance] dataPoints] addObject:vals];
    
    //update the number of data points
    [lblDataPointsCount setText:[NSString stringWithFormat:@"%lu",(unsigned long)[[[TestDetails sharedInstance] dataPoints] count]]];
}

#pragma mark - Convert To JSON
//returns JSON in a readable format (pretty printed)
-(NSString*) getPrettyPrintedJSONforObject:(id)obj
{
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:obj
                                                       options:(NSJSONWritingOptions)    (NSJSONWritingPrettyPrinted)
                                                         error:&error];
    
    if (! jsonData)
    {
        NSLog(@"bv_jsonStringWithPrettyPrint: error: %@", error.localizedDescription);
        return @"{}";
    } else {
        return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
}


#pragma mark - Helper Functions
-(BOOL)dataExists:(NSMutableDictionary*)dataDict
{
    BOOL result = NO;
    for(NSString *key in dataDict.allKeys)
    {
        if(![self isEmpty:[dataDict objectForKey:key]])
        {
            result = YES;
        }
        else
        {
            [dataDict removeObjectForKey:key];
        }
    }
    return result;
}

-(BOOL)isEmpty:(NSString*)str
{
    str = [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    if([str length] == 0)
        return YES;
    else
        return NO;
}

-(void)updateTimer
{
    timeElapsed++;

    //check if time elapsed is greatr than or equal to total walk time, then call save.
    //Also update the time elapsed label
    if(timeElapsed >= [[NSUserDefaults standardUserDefaults] integerForKey:@"total_walk_time"])
    {
        [self save:nil];
    }

    int mins = timeElapsed/60;
    int secs = timeElapsed%60;
    
    NSString *timeString = [NSString stringWithFormat:@"%2d:%2d",mins,secs];
    timeString = [timeString stringByReplacingOccurrencesOfString:@" " withString:@"0"];
    [lblTimeElapsed setText:timeString];
    
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
