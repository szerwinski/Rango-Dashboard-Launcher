import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:liquid_progress_indicator_ns/liquid_progress_indicator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:process_run/shell.dart';
import 'package:window_size/window_size.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setWindowTitle('RanGo Launcher');
  setWindowMinSize(const Size(300, 300));
  setWindowMaxSize(const Size(300, 300));
  PackageInfo packageInfo = await PackageInfo.fromPlatform();

  LaunchAtStartup.instance.setup(
    appName: "RanGo Launcher",
    appPath: Platform.resolvedExecutable,
  );
  await LaunchAtStartup.instance.enable();
  bool isEnabled = await LaunchAtStartup.instance.isEnabled();
  print(isEnabled);
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Material App',
      home: Downloader(),
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
  double percentage = 0;
  var path = Platform.resolvedExecutable.split('rangolauncher.exe')[0];
  var app = Platform.environment["AppData"];
  bool isUnzipping = false;
  bool isCheckin = false;
  CancelToken cancelToken = CancelToken();
  String fileName = '';
  String message = '';
  List<String> filesToDownload = [];
  Future<void> download(String file, String pathToSave) async {
    try {
      var dio = Dio();
      await dio.download(
        'https://s3.sa-east-1.amazonaws.com/rango.dashboard/$file',
        '$pathToSave',
        cancelToken: cancelToken,
        onReceiveProgress: (rcv, total) {
          setState(() {
            percentage = ((rcv / total) * 100);
          });
        },
        deleteOnError: true,
      );
      if (file.contains('.zip') && !cancelToken.isCancelled) {
        setState(() {
          isUnzipping = true;
        });
      }
    } on DioError catch (e) {
      setState(() {
        message = e.message;
      });
    }
  }

  Future<void> unzip() async {
    var shell = Shell();
    var path = '${app}\\rango\\${getZipArchiveName()}';
    setState(() {
      message = 'Descompactando a pasta';
    });
    await shell.run('''
        @echo off
        tar -xf $path -C $app\\rango
    ''');
  }

  void unzipWithArchive() {
    final bytes =
        File('${app}\\rango\\${getZipArchiveName()}').readAsBytesSync();

    // Decode the Zip file
    final archive = ZipDecoder().decodeBytes(bytes);

    // Extract the contents of the Zip archive to disk.
    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        File('${app}\\rango\\' + filename)
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);
      } else {
        Directory('${app}\\rango\\' + filename).create(recursive: true);
      }
    }
  }

  String getZipArchiveName() {
    for (int i = 0; i < filesToDownload.length; i++) {
      if (filesToDownload[i].contains('.zip')) {
        return filesToDownload[i];
      }
    }
    return '';
  }

  Future<void> downloadFiles() async {
    cancelToken = CancelToken();
    setState(() {
      message = 'Transferindo $fileName';
      isUnzipping = false;
    });
    for (int i = 0; i < filesToDownload.length; i++) {
      await download(
          filesToDownload[i], '${app}\\rango\\${filesToDownload[i]}');
    }
  }

  Future<void> launch() async {
    setState(() {
      message = 'Iniciando a aplicação';
    });
    await Shell()
      ..runExecutableArguments('${app}\\rango\\rango_dashboard.exe', []);
  }

  Future<void> closeLauncher() async {
    var shell = Shell();
    await shell.run('''
       @echo off
       taskkill /F /IM rangolauncher.exe
    ''');
  }

  Future<bool> checkIfNeedUpdate() async {
    setState(() {
      isCheckin = true;
      message = 'Checando atualização';
    });
    File verison = File('${app}\\rango\\version.json');
    File dashboard = File('${app}\\rango\\rango_dashboard.exe');
    Response response;
    var dio = Dio();
    response = await dio
        .get('https://s3.sa-east-1.amazonaws.com/rango.dashboard/version.json');
    bool versionExists = await verison.exists();
    bool dashExists = await dashboard.exists();
    if (versionExists && dashExists) {
      final contents = await verison.readAsString();
      var json = jsonDecode(contents);
      if (json["release"] == response.data["release"]) {
        return false;
      } else {
        filesToDownload = new List<String>.from(response.data["files"]);
        return true;
      }
    } else {
      filesToDownload = new List<String>.from(response.data["files"]);
      return true;
    }
  }

  Future<void> syncInit() async {
    bool needUpdate = await checkIfNeedUpdate();
    setState(() {
      isCheckin = false;
    });
    if (needUpdate == true) {
      await downloadFiles();
    } else {
      setState(() {
        percentage = 100;
      });
      await startMakersApplication();
    }
  }

  Future<void> startMakersApplication() async {
    setState(() {
      isUnzipping = false;
    });

    await Future.delayed(Duration(milliseconds: 300));
    await launch();
    await closeLauncher();
  }

  void deleteRemainArchives() {
    final dir = Directory('$app\\rango');
    dir.deleteSync(recursive: true);
  }

  Future<void> restartDownload() async {
    setState(() {
      message = 'Reiniciando o download da aplicação';
    });
    cancelToken.cancel();
    await Future.delayed(Duration(seconds: 1));
    setState(() {
      message = 'Deletando os arquivo e reiniciando o download';
    });
    deleteRemainArchives();
    await downloadFiles();
    if (!cancelToken.isCancelled) {
      await startMakersApplication();
    }
  }

  Widget getDefaultButton(String text, Function onTap) {
    return GestureDetector(
      onTap: () async {
        onTap();
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        child: Text(
          text,
          style: TextStyle(
              color: Colors.orange, fontWeight: FontWeight.w600, fontSize: 16),
        ),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange, width: 2)),
      ),
    );
  }

  @override
  void initState() {
    Future.delayed(Duration.zero, () async {
      await syncInit();
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.blueGrey[800],
      body: SizedBox(
        height: size.height,
        width: size.width,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              isUnzipping
                  ? "Escolha o método de descompactação de arquivos"
                  : message,
              style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                  fontSize: 20),
            ),
            SizedBox(height: 10),
            isUnzipping
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      getDefaultButton(
                        "Padrão",
                        () async {
                          await unzip();
                          startMakersApplication();
                        },
                      ),
                      SizedBox(
                        width: 16,
                      ),
                      getDefaultButton(
                        "Especial",
                        () {
                          unzipWithArchive();
                          startMakersApplication();
                        },
                      )
                    ],
                  )
                : Column(
                    children: [
                      SizedBox(
                        width: 150.0,
                        height: 150.0,
                        child: LiquidCircularProgressIndicator(
                          value: percentage / 100,
                          backgroundColor: Colors.blueGrey[800],
                          valueColor:
                              AlwaysStoppedAnimation(Colors.orange[400]!),
                          borderColor: Colors.orange,
                          borderWidth: 2.0,
                          center: Text(
                            "${percentage.toInt()}%",
                            style: TextStyle(
                              color: Colors.orange[100],
                              fontSize: 20.0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 10,
                      ),
                      getDefaultButton(
                        "Reiniciar download",
                        () async {
                          await restartDownload();
                        },
                      )
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}
