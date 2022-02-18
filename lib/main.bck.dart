import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_size/window_size.dart';
import 'package:process_run/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    setWindowTitle('RanGo Launcher');
    setWindowMinSize(const Size(300, 120));
    setWindowMaxSize(const Size(300, 120));
  }
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  LaunchAtStartup.instance.setup(
    appName: packageInfo.appName,
    appPath: Platform.resolvedExecutable,
  );
  await LaunchAtStartup.instance.enable();
  await LaunchAtStartup.instance.isEnabled();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RanGo Launcher',
      home: Scaffold(backgroundColor: Color(0xFFF58538), body: Downloader()),
      debugShowCheckedModeBanner: false,
    );
  }
}

class Downloader extends StatefulWidget {
  Downloader({Key? key}) : super(key: key);

  @override
  _DownloaderState createState() => _DownloaderState();
}

class _DownloaderState extends State<Downloader> {
  int percentage = 0;

  @override
  Widget build(BuildContext context) {
    Future<void> download(String file, String path) async {
      var dio = Dio();
      await dio.download(
          'https://s3.sa-east-1.amazonaws.com/rango.dashboard/$file', '$path',
          onReceiveProgress: (rcv, total) {
        print(
            'received: ${rcv.toStringAsFixed(0)} out of total: ${total.toStringAsFixed(0)}');

        setState(() {
          percentage = ((rcv / total) * 100).toInt();
        });
      }, deleteOnError: true);
    }

    Future<void> launch() async {
      var windowsVersion = Platform.operatingSystemVersion;
      var path = Platform.resolvedExecutable.split('rangolauncher.exe')[0];
      var shell = Shell();
      Response response;
      var dio = Dio();
      File file = File('$path/rango/version.json');
      bool needUpdate = false;
      //verifica o json
      if (await file.exists() == true) {
        response = await dio.get(
            'https://s3.sa-east-1.amazonaws.com/rango.dashboard/version.json');
        if (response.statusCode == 200) {
          final contents = await file.readAsString();
          var json = jsonDecode(contents);
          if (json["current_version"] != response.data["current_version"]) {
            needUpdate = true;
          }
          file.writeAsString("""${jsonEncode(response.data)}""");
        } else {
          needUpdate = true;
        }
      } else {
        await download('version.json', '$path/rango/version.json');
        needUpdate = true;
      }
      //faz o download se necessario
      if (needUpdate == true) {
        await download('compiled.zip', '$path/rango/rango.zip');

        /*      if (windowsVersion.contains("Windows 10")) {
          await shell.run('''
        @echo off
        tar -xf ${path}rango.zip -C ${path}rango
    ''');
        } else {
          await shell.run('''
        @echo off
        setlocal
        cd /d %~dp0
        Call :UnZipFile "${path}rango" "${path}rango.zip"
        exit /b

        :UnZipFile <ExtractTo> <newzipfile>
        set vbs="%temp%/_.vbs"
        if exist %vbs% del /f /q %vbs%
        >%vbs%  echo Set fso = CreateObject("Scripting.FileSystemObject")
        >>%vbs% echo If NOT fso.FolderExists(%1) Then
        >>%vbs% echo fso.CreateFolder(%1)
        >>%vbs% echo End If
        >>%vbs% echo set objShell = CreateObject("Shell.Application")
        >>%vbs% echo set FilesInZip=objShell.NameSpace(%2).items
        >>%vbs% echo objShell.NameSpace(%1).CopyHere(FilesInZip)
        >>%vbs% echo Set fso = Nothing
        >>%vbs% echo Set objShell = Nothing
        cscript //nologo %vbs%
        if exist %vbs% del /f /q %vbs%
    ''');
        } */
      }
      /* new Shell()
        ..runExecutableArguments('${path}rango\\rango_dashboard.exe', []);
      await shell.run('''
       @echo off
       taskkill /F /IM rangolauncher.exe
    '''); */
    }

    WidgetsBinding.instance!.addPostFrameCallback((_) async {
      await launch();
    });
    return Scaffold(
      body: Center(
        child: Column(
          children: [
            Text(
              'Atualizando componentes $percentage%',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 20),
            ),
            SizedBox(height: 10),
            CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white))
          ],
        ),
      ),
    );
  }
}
