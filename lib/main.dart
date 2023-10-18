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
  bool showUnzipOptions = false;
  bool unzipping = false;
  bool isCheckin = false;
  CancelToken cancelToken = CancelToken();
  String fileName = '';
  String message = '';
  String? compileError;
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
          showUnzipOptions = true;
        });
      }
    } on DioError catch (e) {
      setState(() {
        message = e.message;
      });
    }
  }

  Future<void> unzip() async {
    setState(() {
      compileError = null;
      unzipping = true;
      message = 'Descompactando a pasta';
    });
    var shell = Shell();
    var path = '${app}\\rango\\${getZipArchiveName()}';
    await shell.run('''
        @echo off
        tar -xf $path -C $app\\rango
    ''');
    setState(() {
      unzipping = false;
    });
  }

  Future<void> unzipWithArchive() async {
    setState(() {
      compileError = null;
      unzipping = true;
      message = 'Descompactando a pasta';
    });

    await Future.delayed(Duration(seconds: 1));
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
    setState(() {
      unzipping = false;
    });
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
      showUnzipOptions = false;
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
    var shell = Shell();
    Directory.current = '$app\\rango';
    await shell
      ..runExecutableArguments('rango_dashboard.exe', []);
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
      print(json["release"]);
      print(response.data["release"]);
      print(json["release"] == response.data["release"]);
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
      showUnzipOptions = false;
    });

    await Future.delayed(Duration(milliseconds: 300));
    await launch();
    await closeLauncher();
  }

  void deleteRemainArchives() {
    final dir = Directory('$app\\rango');
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }

  Future<void> restartDownload() async {
    setState(() {
      message = 'Reiniciando o download da aplicação';
    });
    if (!cancelToken.isCancelled) {
      cancelToken.cancel();
    }
    await Future.delayed(Duration(seconds: 1));
    setState(() {
      message = 'Deletando os arquivo e reiniciando o download';
    });
    try {
      deleteRemainArchives();
      if (filesToDownload.isEmpty) {
        syncInit();
      } else {
        await downloadFiles();
      }
    } catch (e) {
      print(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString()),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 10),
      ));
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
              showUnzipOptions
                  ? unzipping
                      ? message
                      : "Escolha o método de descompactação de arquivos"
                  : message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                  fontSize: 20),
            ),
            SizedBox(height: 10),
            showUnzipOptions
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: unzipping
                        ? [
                            CircularProgressIndicator(
                              color: Colors.orange,
                            )
                          ]
                        : [
                            getDefaultButton(
                              "Padrão",
                              () async {
                                try {
                                  await unzip();
                                  await startMakersApplication();
                                } catch (err) {
                                  setState(() {
                                    showUnzipOptions = true;
                                    unzipping = false;
                                    compileError =
                                        'Ocorreu um erro no método padrão, selecione o método especial';
                                  });
                                  print(err);
                                }
                              },
                            ),
                            SizedBox(
                              width: 16,
                            ),
                            getDefaultButton(
                              "Especial",
                              () async {
                                try {
                                  await unzipWithArchive();
                                  await startMakersApplication();
                                } catch (err) {
                                  setState(() {
                                    showUnzipOptions = true;
                                    unzipping = false;
                                    compileError =
                                        'Ocorreu um erro no método especial, selecione o método padrão';
                                  });
                                }
                              },
                            ),
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
            SizedBox(
              height: 10,
            ),
            if (compileError != null)
              Text(
                compileError!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                    fontSize: 14),
              ),
          ],
        ),
      ),
    );
  }
}
