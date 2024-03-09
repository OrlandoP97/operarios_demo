import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:lottie/lottie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await requestLocationPermissions();
  await requestNotificationPermission();
  await _determinePosition();
  await initializeService();

  runApp(const MyApp());
}

Future<void> requestNotificationPermission() async {
  PermissionStatus status = await Permission.notification.status;
  if (status.isDenied) {
    // We didn't ask for permission yet or the permission has been denied before but not permanently.
    PermissionStatus newStatus = await Permission.notification.request();
    if (newStatus.isGranted) {
      print('Notification permission granted');
      // Proceed with notification-related functionality
    } else if (newStatus.isDenied) {
      print('Notification permission denied');
      // The user denied the permission.
    }
  } else if (status.isGranted) {
    print('Notification permission already granted');
    // Proceed with notification-related functionality
  }
}

Future<void> requestLocationPermissions() async {
  // Request 'locationWhenInUse' permission
  var status = await Permission.locationWhenInUse.status;
  if (!status.isGranted) {
    status = await Permission.locationWhenInUse.request();
    if (status.isGranted) {
      // If 'locationWhenInUse' is granted, request 'locationAlways'
      status = await Permission.locationAlways.request();
      if (status.isGranted) {
        // Permission granted
      } else {
        // Handle permission not granted
      }
    } else {
      // Handle permission not granted
    }
  } else {
    // 'locationWhenInUse' is already granted, request 'locationAlways'
    status = await Permission.locationAlways.request();
    if (status.isGranted) {
      // Permission granted
    } else {
      // Handle permission not granted
    }
  }
}

Future<Position> _determinePosition() async {
  bool serviceEnabled;
  LocationPermission permission;

  // continue accessing the position of the device.
  Position position = await Geolocator.getCurrentPosition();

  // Save the current altitude to SharedPreferences
  SharedPreferences preferences = await SharedPreferences.getInstance();
  double? previousAltitude = preferences.getDouble('previousAltitude');
  await preferences.setDouble('currentAltitude', position.altitude);

  // If there's a previous altitude, save it as the previous altitude
  if (previousAltitude != null) {
    await preferences.setDouble('previousAltitude', previousAltitude);
  } else {
    // Update the previous altitude with the current altitude for the next call
    await preferences.setDouble('previousAltitude', position.altitude);
  }
  return position;
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  /// OPTIONAL, using custom notification channel id
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'my_foreground', // id
    'MY FOREGROUND SERVICE', // title
    description:
        'This channel is used for important notifications.', // description
    importance: Importance.high, // importance must be at low or higher level
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (Platform.isIOS || Platform.isAndroid) {
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        iOS: DarwinInitializationSettings(),
        android: AndroidInitializationSettings('ic_bg_service_small'),
      ),
    );
  }

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      // this will be executed when app is in foreground or background in separated isolate
      onStart: onStart,

      // auto start service
      autoStart: true,
      isForegroundMode: false,

      notificationChannelId: 'my_foreground',
      initialNotificationTitle: 'INICIANDO SERVICIO DE POSIBLE CAÍDA',
      initialNotificationContent: 'Started',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      // auto start service
      autoStart: true,

      // this will be executed when app is in foreground in separated isolate
      onForeground: onStart,

      // you have to enable background fetch capability on xcode project
      onBackground: onIosBackground,
    ),
  );
}

// to ensure this is executed
// run app from xcode, then from xcode menu, select Simulate Background Fetch

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  SharedPreferences preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  final log = preferences.getStringList('log') ?? <String>[];
  log.add(DateTime.now().toIso8601String());
  await preferences.setStringList('log', log);

  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Only available for flutter 3.0.0 and later
  DartPluginRegistrant.ensureInitialized();

  // For flutter prior to version 3.0.0
  // We have to register the plugin manually

  SharedPreferences preferences = await SharedPreferences.getInstance();
  await preferences.setString("hello", "world");

  /// OPTIONAL when use custom notification
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // bring to foreground
  Timer.periodic(const Duration(seconds: 5), (timer) async {
    print("value tic tac");
    await _determinePosition();

    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final prevAltitude = prefs.getDouble('previousAltitude');
    final currentAltitude = prefs.getDouble('currentAltitude');
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        final value = currentAltitude! - prevAltitude!.abs();
        print("value $value");
        if ((currentAltitude! - prevAltitude!).abs() > 1) {
          print("CALLED");
          flutterLocalNotificationsPlugin.show(
            888,
            'POSIBLE CAÍDA',
            'Cambio de altitud repentino! ${currentAltitude} ',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'my_foreground',
                'MY FOREGROUND SERVICE',
                icon: 'ic_bg_service_small',
                ongoing: true,
              ),
            ),
          );
        }

        // if you don't using custom notification, uncomment this
        /*  service.setForegroundNotificationInfo(
          title: "My App Service",
          content: "Updated at ${DateTime.now()} aaa",
        ); */
      }
    }

    /// you can see this log in logcat
    print('FLUTTER BACKGROUND SERVICE: ${DateTime.now()}');

    service.invoke(
      'update',
      {
        "current_date": DateTime.now().toIso8601String(),
        "altitude": currentAltitude.toString()
      },
    );
  });
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String text = "Stop Service";
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Detector de caídas',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.redAccent,
        ),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Lottie.asset(
              "assets/falling.json",
              fit: BoxFit.contain,
            ),
            StreamBuilder<Map<String, dynamic>?>(
              stream: FlutterBackgroundService().on('update'),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final data = snapshot.data!;

                String altitude =
                    data["altitude"] ?? "No selected altitude yet";

                return Center(
                  child: Column(
                    children: [Text(altitude)],
                  ),
                );
              },
            ),
            ElevatedButton(
              child: const Text("Foreground Mode"),
              onPressed: () {
                FlutterBackgroundService().invoke("setAsForeground");
              },
            ),
            ElevatedButton(
              child: const Text("Background Mode"),
              onPressed: () {
                FlutterBackgroundService().invoke("setAsBackground");
              },
            ),
            ElevatedButton(
              child: Text(text),
              onPressed: () async {
                final service = FlutterBackgroundService();
                var isRunning = await service.isRunning();
                if (isRunning) {
                  service.invoke("stopService");
                } else {
                  service.startService();
                }

                if (!isRunning) {
                  text = 'Stop Service';
                } else {
                  text = 'Start Service';
                }
                setState(() {});
              },
            ),
            /*   const Expanded(
              child: LogView(),
            ), */
          ],
        ),
      ),
    );
  }
}
