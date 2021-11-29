import 'dart:async';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'preview_screen.dart';

class CameraApp extends StatefulWidget {
  final VideoPlayerController duetVideoController;
  final VoidCallback onCancleRecording;

  const CameraApp({
    Key? key,
    required this.duetVideoController,
    required this.onCancleRecording,
  }) : super(key: key);

  @override
  _CameraAppState createState() => _CameraAppState();
}

class _CameraAppState extends State<CameraApp> {
  List<CameraDescription>? cameras;
  CameraController? cameraController;

  bool isInitCamera = false;
  bool isInitVideo = false;

  XFile? videoFile;
  String? cache;

  //listen to duet video
  bool _isPlaying = false;
  Duration? _duration;
  Duration? _position;

  //duet video merging size
  static const VERTICAL_DUET_WIDTH = 360;
  static const VERTICAL_DUET_HEIGHT = 640;
  late double videoWidth, videoHeight, paddingVer, paddingHoz = 0;

  //show loading when process video
  bool _showLoading = false;

  void initCamera() async {
    cameras = await availableCameras();
    cache = (await getTemporaryDirectory()).path;
    cameraController = CameraController(cameras![1], ResolutionPreset.max);
    cameraController!.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        isInitCamera = true;
      });
    });
  }

  void initVideo() {
    widget.duetVideoController
      ..addListener(() {
        final bool isPlaying = widget.duetVideoController.value.isPlaying;
        if (isPlaying != _isPlaying) {
          setState(() {
            _isPlaying = isPlaying;
          });
        }
        Timer.run(() {
          setState(() {
            _position = widget.duetVideoController.value.position;
          });
        });
        setState(() {
          _duration = widget.duetVideoController.value.duration;
        });
        _duration?.compareTo(_position!) == 0 ||
                _duration?.compareTo(_position!) == -1
            ? setState(() {
                //stop when the duetvideo end
                onStopButtonPressed();
              })
            : setState(() {});
      })
      ..initialize().then((_) {
        // Ensure the first frame is shown after the video is initialized, even before the play button has been pressed.
        setState(() {
          isInitVideo = true;
        });
      });
  }

  @override
  void initState() {
    super.initState();
    initVideo();
    initCamera();
  }

  @override
  void dispose() {
    cameraController?.dispose();
    widget.duetVideoController.dispose();
    super.dispose();
  }

  void resizeInput() {
    double orginalWidth = widget.duetVideoController.value.size.width;
    double orginalHeight = widget.duetVideoController.value.size.height;

    double resizeFactor = min(VERTICAL_DUET_WIDTH / orginalWidth,
        VERTICAL_DUET_HEIGHT / orginalHeight);

    videoWidth = orginalWidth * resizeFactor;
    videoHeight = orginalHeight * resizeFactor;
    paddingHoz = (VERTICAL_DUET_WIDTH - videoWidth) / 2;
    paddingVer = (VERTICAL_DUET_HEIGHT - videoHeight) / 2;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        body: Stack(
          children: [
            Container(
              height: MediaQuery.of(context).size.height,
              width: MediaQuery.of(context).size.width,
              color: Colors.black,
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(1.0),
                      child: isInitCamera && isInitVideo
                          ? Row(
                              children: [
                                Expanded(
                                    child: FractionallySizedBox(
                                        //heightFactor: 0.5,
                                        child: AspectRatio(
                                            aspectRatio: 1 /
                                                cameraController!
                                                    .value.aspectRatio,
                                            child: CameraPreview(
                                                cameraController!)))),
                                Expanded(
                                    child: FractionallySizedBox(
                                        child: AspectRatio(
                                            aspectRatio: widget
                                                .duetVideoController
                                                .value
                                                .aspectRatio,
                                            child: VideoPlayer(
                                                widget.duetVideoController)))),
                              ],
                            )
                          : const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                  VideoProgressIndicator(
                    widget.duetVideoController,
                    allowScrubbing: false,
                  ),
                ],
              ),
            ),
            Positioned(
                top: 20,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  iconSize: 30,
                  color: Colors.white,
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(10),
                          topRight: Radius.circular(10),
                        ),
                      ),
                      backgroundColor: Colors.white,
                      builder: (BuildContext context) {
                        return Wrap(
                          children: [
                            Column(
                              children: [
                                ListTile(
                                  leading: const Icon(
                                    Icons.refresh,
                                    color: Colors.black,
                                  ),
                                  title: const Text(
                                    "Re-make recording",
                                    style: TextStyle(color: Colors.black),
                                  ),
                                  onTap: () {
                                    remakeRecording();
                                    Navigator.pop(context);
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  title: const Text(
                                    "Cancle recording",
                                    style: TextStyle(color: Colors.red),
                                  ),
                                  onTap: () => widget.onCancleRecording,
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    );
                  },
                )),
            Positioned(
                bottom: 20,
                right: 0,
                left: 0,
                child: _captureControlRowWidget()),
            if (_showLoading)
              const Center(
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _captureControlRowWidget() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: <Widget>[
        const SizedBox(width: 30),
        IconButton(
          iconSize: 100,
          color: Colors.red,
          icon: cameraController != null &&
                  cameraController!.value.isRecordingVideo &&
                  !cameraController!.value.isRecordingPaused
              ? const Icon(
                  Icons.stop_circle_outlined,
                )
              : const Icon(
                  Icons.radio_button_on,
                ),
          onPressed:
              cameraController != null && cameraController!.value.isInitialized
                  ? (cameraController!.value.isRecordingVideo)
                      ? (cameraController!.value.isRecordingPaused)
                          ? onResumeButtonPressed
                          : onPauseButtonPressed
                      : onVideoRecordButtonPressed
                  : onVideoRecordButtonPressed,
        ),
        IconButton(
          icon: const Icon(Icons.check_circle),
          color: Colors.red,
          iconSize: 30,
          onPressed: cameraController != null &&
                  cameraController!.value.isInitialized &&
                  cameraController!.value.isRecordingVideo
              ? onStopButtonPressed
              : null,
        ),
      ],
    );
  }

  void remakeRecording() {
    setState(() {
      cameraController!.stopVideoRecording();
      widget.duetVideoController.pause();
      print(widget.duetVideoController.dataSource);
      widget.duetVideoController.seekTo(const Duration(seconds: 0));
    });
  }

  void onStopButtonPressed() {
    widget.duetVideoController.pause();
    stopVideoRecording().then((file) async {
      if (mounted) setState(() {});
      if (file != null) {
        videoFile = file;
        resizeInput();
        String filter = //" [0:v]scale=1080:-1[v0];[v0][1:v]vstack=inputs=2 ";
            " [0:v]setpts=PTS-STARTPTS,scale=$VERTICAL_DUET_WIDTH:$VERTICAL_DUET_HEIGHT,fps=60,setsar=1[l];"
            "[1:v]setpts=PTS-STARTPTS,scale=$videoWidth:$videoHeight,pad=$VERTICAL_DUET_WIDTH:$VERTICAL_DUET_HEIGHT:$paddingHoz:$paddingVer,fps=60,setsar=1[r];"
            "[l][r]hstack=inputs=2:shortest=1,format=yuv420p;[0][1]amerge ";

        setState(() {
          _showLoading = true;
        });

        await FlutterFFmpeg()
            .execute(" -y -i " +
                videoFile!.path +
                " -i " +
                widget.duetVideoController.dataSource +
                " -filter_complex" +
                filter +
                "-c:v libx264 -crf 20 -c:a aac -strict -2 " +
                //"-c:v mpeg2video -q:v 3 " +
                "$cache/duetvideo.mp4")
            .then((_) => {
                  setState(() {
                    _showLoading = false;
                  })
                });

        await GallerySaver.saveVideo("$cache/duetvideo.mp4");
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  PreviewVideo(videoPath: XFile("$cache/duetvideo.mp4"))),
        );
      }
    });
  }

  void onVideoRecordButtonPressed() {
    startVideoRecording().then((_) {
      if (mounted) setState(() {});
    });
  }

  void onResumeButtonPressed() {
    resumeVideoRecording().then((_) {
      if (mounted) setState(() {});
      print('Video recording resumed');
    });
  }

  void onPauseButtonPressed() {
    pauseVideoRecording().then((_) {
      if (mounted) setState(() {});
      print('Video recording paused');
    });
  }

  Future<void> startVideoRecording() async {
    if (cameraController!.value.isRecordingVideo) {
      // A recording is already started, do nothing.
      return;
    }

    try {
      await cameraController!.startVideoRecording();
      widget.duetVideoController.play();
    } on CameraException catch (e) {
      print(e);
      return;
    }
  }

  Future<void> resumeVideoRecording() async {
    if (cameraController == null || !cameraController!.value.isRecordingVideo) {
      return null;
    }

    try {
      await cameraController!.resumeVideoRecording();
      widget.duetVideoController.play();
    } on CameraException catch (e) {
      print(e);
      rethrow;
    }
  }

  Future<void> pauseVideoRecording() async {
    if (cameraController == null || !cameraController!.value.isRecordingVideo) {
      return null;
    }

    try {
      await cameraController!.pauseVideoRecording();
      widget.duetVideoController.pause();
    } on CameraException catch (e) {
      print(e);
      rethrow;
    }
  }

  Future<XFile?> stopVideoRecording() async {
    if (cameraController == null || !cameraController!.value.isRecordingVideo) {
      return null;
    }

    try {
      return cameraController!.stopVideoRecording();
    } on CameraException catch (e) {
      print(e);
      return null;
    }
  }
}
