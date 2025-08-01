import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/main.dart';
import 'package:PiliPlus/models/common/episode_panel_type.dart';
import 'package:PiliPlus/models/common/search_type.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/episode.dart' as pgc;
import 'package:PiliPlus/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliPlus/models_new/video/video_detail/episode.dart';
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/models_new/video/video_tag/data.dart';
import 'package:PiliPlus/pages/danmaku/view.dart';
import 'package:PiliPlus/pages/episode_panel/view.dart';
import 'package:PiliPlus/pages/video/ai_conclusion/view.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/introduction/pgc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/pgc/view.dart';
import 'package:PiliPlus/pages/video/introduction/pgc/widgets/intro_detail.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/view.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/widgets/page.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/widgets/season.dart';
import 'package:PiliPlus/pages/video/member/controller.dart';
import 'package:PiliPlus/pages/video/member/view.dart';
import 'package:PiliPlus/pages/video/related/view.dart';
import 'package:PiliPlus/pages/video/reply/controller.dart';
import 'package:PiliPlus/pages/video/reply/view.dart';
import 'package:PiliPlus/pages/video/reply_reply/view.dart';
import 'package:PiliPlus/pages/video/view_point/view.dart';
import 'package:PiliPlus/pages/video/widgets/header_control.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:PiliPlus/plugin/pl_player/view.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/services/shutdown_timer_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/extension.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/image_util.dart';
import 'package:PiliPlus/utils/num_util.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:auto_orientation/auto_orientation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:floating/floating.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:screen_brightness/screen_brightness.dart';

class VideoDetailPageV extends StatefulWidget {
  const VideoDetailPageV({super.key});

  @override
  State<VideoDetailPageV> createState() => _VideoDetailPageVState();
  static final RouteObserver<PageRoute> routeObserver =
      RouteObserver<PageRoute>();
}

class _VideoDetailPageVState extends State<VideoDetailPageV>
    with TickerProviderStateMixin, RouteAware, WidgetsBindingObserver {
  late VideoDetailController videoDetailController;
  late VideoReplyController _videoReplyController;
  PlPlayerController? plPlayerController;
  late VideoIntroController videoIntroController;
  late PgcIntroController pgcIntroController;
  late final _introController = ScrollController();
  late String heroTag;

  bool get autoExitFullscreen =>
      videoDetailController.plPlayerController.autoExitFullscreen;
  bool get autoPlayEnable =>
      videoDetailController.plPlayerController.autoPlayEnable;
  bool get enableVerticalExpand =>
      videoDetailController.plPlayerController.enableVerticalExpand;
  bool get pipNoDanmaku =>
      videoDetailController.plPlayerController.pipNoDanmaku;
  bool get removeSafeArea =>
      videoDetailController.plPlayerController.removeSafeArea;

  bool isShowing = true;
  bool get isFullScreen => plPlayerController?.isFullScreen.value ?? false;

  bool get _shouldShowSeasonPanel {
    final videoDetail = videoIntroController.videoDetail.value;
    return (videoDetail.ugcSeason != null ||
            ((videoDetail.pages?.length ?? 0) > 1)) &&
        context.orientation == Orientation.landscape &&
        videoDetailController.plPlayerController.horizontalSeasonPanel;
  }

  bool get _horizontalPreview =>
      context.orientation == Orientation.landscape &&
      videoDetailController.plPlayerController.horizontalPreview;

  StreamSubscription? _listenerFS;

  final GlobalKey relatedVideoPanelKey = GlobalKey();
  final GlobalKey videoPlayerKey = GlobalKey();
  final GlobalKey videoReplyPanelKey = GlobalKey();
  late final GlobalKey ugcPanelKey = GlobalKey();
  late final GlobalKey pgcPanelKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    PlPlayerController.setPlayCallBack(playCallBack);
    if (Get.arguments != null && Get.arguments['heroTag'] != null) {
      heroTag = Get.arguments['heroTag'];
    }
    videoDetailController = Get.put(VideoDetailController(), tag: heroTag);

    if (videoDetailController.showReply) {
      _videoReplyController = Get.put(
        VideoReplyController(aid: videoDetailController.oid.value),
        tag: heroTag,
      );
    }
    videoIntroController = Get.put(VideoIntroController(), tag: heroTag);
    if (videoDetailController.videoType == SearchType.media_bangumi) {
      pgcIntroController = Get.put(PgcIntroController(), tag: heroTag);
    }

    if (removeSafeArea) hideStatusBar();
    videoSourceInit();
    autoScreen();

    if (videoDetailController.showReply) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        videoDetailController.scrollKey.currentState?.innerController
            .addListener(innerScrollListener);
      });
    }

    videoDetailController.animationController.addListener(animListener);

    _listenerFS = videoDetailController.plPlayerController.isFullScreen.listen((
      value,
    ) {
      refreshPage();
    });

    WidgetsBinding.instance.addObserver(this);
  }

  // 获取视频资源，初始化播放器
  Future<void> videoSourceInit() async {
    videoDetailController.queryVideoUrl();
    if (videoDetailController.autoPlay.value) {
      plPlayerController = videoDetailController.plPlayerController;
      plPlayerController!.addStatusLister(playerListener);
      plPlayerController!.addPositionListener(positionListener);
      await plPlayerController!.autoEnterFullscreen();
    }
  }

  void positionListener(Duration position) {
    videoDetailController.playedTime = position;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      videoIntroController.startTimer();
      videoDetailController.plPlayerController.showDanmaku = true;
    } else if (state == AppLifecycleState.paused) {
      videoIntroController.canelTimer();
      videoDetailController.plPlayerController.showDanmaku = false;
    }
  }

  void playCallBack() {
    plPlayerController?.play();
  }

  // 播放器状态监听
  Future<void> playerListener(PlayerStatus? status) async {
    try {
      if (videoDetailController.scrollCtr.hasClients) {
        bool isPlaying = status == PlayerStatus.playing;
        if (isPlaying) {
          if (!videoDetailController.isExpanding &&
              videoDetailController.scrollCtr.offset != 0 &&
              !videoDetailController.animationController.isAnimating) {
            videoDetailController.isExpanding = true;
            videoDetailController.animationController.forward(
              from:
                  1 -
                  videoDetailController.scrollCtr.offset /
                      videoDetailController.videoHeight,
            );
          } else {
            refreshPage();
          }
        } else {
          refreshPage();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('handle playe status: $e');
    }

    if (status == PlayerStatus.completed) {
      try {
        if (videoDetailController
                .steinEdgeInfo
                ?.edges
                ?.questions
                ?.firstOrNull
                ?.choices
                ?.isNotEmpty ==
            true) {
          videoDetailController.showSteinEdgeInfo.value = true;
          return;
        }
      } catch (_) {}
      shutdownTimerService.handleWaitingFinished();
      bool notExitFlag = false;

      /// 顺序播放 列表循环
      if (plPlayerController!.playRepeat != PlayRepeat.pause &&
          plPlayerController!.playRepeat != PlayRepeat.singleCycle) {
        if (videoDetailController.isPlayAll ||
            videoDetailController.videoType == SearchType.video) {
          notExitFlag = videoIntroController.nextPlay();
        } else if (videoDetailController.videoType ==
            SearchType.media_bangumi) {
          notExitFlag = pgcIntroController.nextPlay();
        }
      }

      /// 单个循环
      if (plPlayerController!.playRepeat == PlayRepeat.singleCycle) {
        notExitFlag = true;
        plPlayerController!.play(repeat: true);
      }

      // 结束播放退出全屏
      if (!notExitFlag && autoExitFullscreen) {
        plPlayerController!.triggerFullScreen(status: false);
        if (plPlayerController!.longPressStatus.value) {
          plPlayerController!.setLongPressStatus(false);
        }
        if (plPlayerController!.controlsLock.value) {
          plPlayerController!.onLockControl(false);
        }
      }
      // 播放完展示控制栏
      if (Platform.isAndroid && !notExitFlag) {
        PiPStatus currentStatus = await Floating().pipStatus;
        if (currentStatus == PiPStatus.disabled) {
          plPlayerController!.onLockControl(false);
        }
      }
    }
  }

  // 继续播放或重新播放
  void continuePlay() {
    plPlayerController!.play();
  }

  /// 未开启自动播放时触发播放
  Future<void> handlePlay() async {
    if (videoDetailController.isQuerying) {
      if (kDebugMode) debugPrint('handlePlay: querying');
      return;
    }
    if (videoDetailController.videoUrl == null ||
        videoDetailController.audioUrl == null) {
      if (kDebugMode) {
        debugPrint('handlePlay: videoUrl/audioUrl not initialized');
      }
      videoDetailController.queryVideoUrl();
      return;
    }
    plPlayerController = videoDetailController.plPlayerController;
    videoDetailController.isShowCover.value = false;
    videoDetailController.autoPlay.value = true;
    if (videoDetailController.plPlayerController.preInitPlayer) {
      await plPlayerController!.play();
    } else {
      await videoDetailController.playerInit(autoplay: true);
    }
    plPlayerController!.addStatusLister(playerListener);
    plPlayerController!.addPositionListener(positionListener);
    await plPlayerController!.autoEnterFullscreen();
  }

  @override
  void dispose() {
    _listenerFS?.cancel();

    videoDetailController.skipTimer?.cancel();
    videoDetailController.skipTimer = null;

    try {
      Get.delete<HorizontalMemberPageController>(
        tag: videoDetailController.heroTag,
      );
      videoDetailController.animationController.removeListener(animListener);
      if (videoDetailController.showReply) {
        videoDetailController.scrollKey.currentState?.innerController
            .removeListener(innerScrollListener);
      }
    } catch (_) {}

    WidgetsBinding.instance.removeObserver(this);
    if (!Get.previousRoute.startsWith('/video')) {
      ScreenBrightness().resetApplicationScreenBrightness();
      PlPlayerController.setPlayCallBack(null);
    }
    videoDetailController.positionSubscription?.cancel();
    videoIntroController.canelTimer();
    videoIntroController.videoDetail.close();
    videoDetailController.cid.close();
    if (!videoDetailController.horizontalScreen) {
      AutoOrientation.portraitUpMode();
    }
    shutdownTimerService.handleWaitingFinished();
    if (videoDetailController.plPlayerController.backToHome != true) {
      videoPlayerServiceHandler.onVideoDetailDispose(heroTag);
    }
    if (plPlayerController != null) {
      videoDetailController.makeHeartBeat();
      plPlayerController!.removeStatusLister(playerListener);
      plPlayerController!.removePositionListener(positionListener);
      plPlayerController!.dispose();
    } else {
      PlPlayerController.updatePlayCount();
    }
    VideoDetailPageV.routeObserver.unsubscribe(this);
    showStatusBar();
    super.dispose();
  }

  @override
  // 离开当前页面时
  Future<void> didPushNext() async {
    if (videoDetailController.imageStatus) {
      return;
    }

    WidgetsBinding.instance.removeObserver(this);

    ScreenBrightness().resetApplicationScreenBrightness();

    videoDetailController.positionSubscription?.cancel();
    videoIntroController.canelTimer();

    videoDetailController
      ..playerStatus = plPlayerController?.playerStatus.status.value
      ..brightness = plPlayerController?.brightness.value;
    if (plPlayerController != null) {
      videoDetailController
        ..makeHeartBeat()
        ..showVP = plPlayerController!.showVP.value;
      plPlayerController!.removeStatusLister(playerListener);
      plPlayerController!.removePositionListener(positionListener);
      plPlayerController!.pause();
    }
    isShowing = false;
    super.didPushNext();
  }

  @override
  // 返回当前页面时
  Future<void> didPopNext() async {
    if (videoDetailController.imageStatus) {
      return;
    }

    WidgetsBinding.instance.addObserver(this);

    if (videoDetailController.plPlayerController.playerStatus.status.value ==
            PlayerStatus.playing &&
        videoDetailController.playerStatus != PlayerStatus.playing) {
      videoDetailController.plPlayerController.pause();
    }

    isShowing = true;
    PlPlayerController.setPlayCallBack(playCallBack);
    videoIntroController.startTimer();
    if (mounted) {
      if (videoDetailController.brightness != null) {
        plPlayerController?.setCurrBrightness(
          videoDetailController.brightness!,
        );
        if (videoDetailController.brightness != -1.0) {
          ScreenBrightness().setApplicationScreenBrightness(
            videoDetailController.brightness!,
          );
        } else {
          ScreenBrightness().resetApplicationScreenBrightness();
        }
      } else {
        ScreenBrightness().resetApplicationScreenBrightness();
      }
    }
    super.didPopNext();
    final isShowCover = videoDetailController.isShowCover.value;
    videoDetailController.autoPlay.value = !isShowCover;
    if (!isShowCover) {
      await videoDetailController.playerInit(
        autoplay: videoDetailController.playerStatus == PlayerStatus.playing,
      );
    } else if (videoDetailController.plPlayerController.preInitPlayer &&
        !videoDetailController.isQuerying &&
        videoDetailController.videoState.value is! Error) {
      await videoDetailController.playerInit();
    }

    Future.delayed(const Duration(milliseconds: 600), () {
      AutoOrientation.fullAutoMode();
    });
    plPlayerController?.addStatusLister(playerListener);
    plPlayerController?.addPositionListener(positionListener);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    VideoDetailPageV.routeObserver.subscribe(
      this,
      ModalRoute.of(context)! as PageRoute,
    );
    themeData = videoDetailController.plPlayerController.darkVideoPage
        ? MyApp.darkThemeData ?? Theme.of(context)
        : Theme.of(context);
  }

  void animListener() {
    if (videoDetailController.animationController.isForwardOrCompleted) {
      cal();
      refreshPage();
    }
  }

  late double animHeight;
  void cal() {
    if (videoDetailController.isExpanding) {
      animHeight = clampDouble(
        videoDetailController.videoHeight *
            videoDetailController.animationController.value,
        kToolbarHeight,
        videoDetailController.videoHeight,
      );
    } else if (videoDetailController.isCollapsing) {
      animHeight = clampDouble(
        videoDetailController.maxVideoHeight -
            (videoDetailController.maxVideoHeight -
                    videoDetailController.minVideoHeight) *
                videoDetailController.animationController.value,
        videoDetailController.minVideoHeight,
        videoDetailController.maxVideoHeight,
      );
    }
  }

  void innerScrollListener() {
    final ScrollDirection? direction = videoDetailController
        .scrollKey
        .currentState
        ?.innerController
        .positions
        .firstOrNull
        ?.userScrollDirection;
    if (direction == ScrollDirection.forward) {
      if (mounted) {
        _videoReplyController.showFab();
      }
    } else if (direction == ScrollDirection.reverse) {
      if (mounted) {
        _videoReplyController.hideFab();
      }
    }
  }

  void refreshPage() {
    if (videoDetailController.scrollKey.currentState?.mounted == true) {
      videoDetailController.scrollKey.currentState?.setState(() {});
    }
  }

  Widget get childWhenDisabled {
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final useSafeArea = !removeSafeArea && isPortrait && isFullScreen;
    final size = MediaQuery.sizeOf(context);
    final double width = size.width;
    final double height = size.height;
    return SafeArea(
      top: useSafeArea,
      bottom: useSafeArea,
      left: false,
      right: false,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        key: videoDetailController.scaffoldKey,
        appBar: (removeSafeArea || isFullScreen)
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(0),
                child: Obx(
                  () {
                    final scrollRatio = videoDetailController.scrollRatio.value;
                    bool shouldShow =
                        scrollRatio != 0 &&
                        videoDetailController.scrollCtr.offset != 0 &&
                        isPortrait;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AppBar(
                          backgroundColor: Colors.black,
                          toolbarHeight: 0,
                          systemOverlayStyle: Platform.isAndroid
                              ? shouldShow
                                    ? null
                                    : SystemUiOverlayStyle(
                                        statusBarIconBrightness:
                                            Brightness.light,
                                        systemNavigationBarIconBrightness:
                                            themeData.brightness.reverse,
                                      )
                              : null,
                        ),
                        if (shouldShow)
                          AppBar(
                            backgroundColor: themeData.colorScheme.surface
                                .withValues(alpha: scrollRatio),
                            toolbarHeight: 0,
                            systemOverlayStyle: Platform.isAndroid
                                ? SystemUiOverlayStyle(
                                    statusBarIconBrightness:
                                        themeData.brightness.reverse,
                                    systemNavigationBarIconBrightness:
                                        themeData.brightness.reverse,
                                  )
                                : null,
                          ),
                      ],
                    );
                  },
                ),
              ),
        body: ExtendedNestedScrollView(
          key: videoDetailController.scrollKey,
          physics: const NeverScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          controller: videoDetailController.scrollCtr,
          onlyOneScrollInBody: true,
          pinnedHeaderSliverHeightBuilder: () {
            double pinnedHeight =
                isFullScreen ||
                    MediaQuery.orientationOf(context) == Orientation.landscape
                ? MediaQuery.sizeOf(context).height
                : videoDetailController.isExpanding ||
                      videoDetailController.isCollapsing
                ? animHeight
                : videoDetailController.isCollapsing ||
                      plPlayerController?.playerStatus.status.value ==
                          PlayerStatus.playing
                ? videoDetailController.minVideoHeight
                : kToolbarHeight;
            if (videoDetailController.isExpanding &&
                videoDetailController.animationController.value == 1) {
              videoDetailController.isExpanding = false;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                videoDetailController.scrollRatio.value = 0;
                refreshPage();
              });
            } else if (videoDetailController.isCollapsing &&
                videoDetailController.animationController.value == 1) {
              videoDetailController.isCollapsing = false;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                refreshPage();
              });
            }
            return pinnedHeight;
          },
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverAppBar(
                elevation: 0,
                scrolledUnderElevation: 0,
                primary: false,
                automaticallyImplyLeading: false,
                pinned: true,
                expandedHeight: isFullScreen || !isPortrait
                    ? height
                    : videoDetailController.isExpanding ||
                          videoDetailController.isCollapsing
                    ? animHeight
                    : videoDetailController.videoHeight,
                flexibleSpace: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Builder(
                      builder: (context) {
                        if (!isPortrait &&
                            !videoDetailController.horizontalScreen &&
                            !isFullScreen &&
                            isShowing &&
                            mounted) {
                          hideStatusBar();
                        }
                        if (isPortrait &&
                            !isFullScreen &&
                            isShowing &&
                            mounted) {
                          if (!videoDetailController.imageStatus &&
                              !removeSafeArea) {
                            showStatusBar();
                          }
                        }
                        return SizedBox(
                          height: !isPortrait || isFullScreen
                              ? height -
                                    (!isPortrait || removeSafeArea
                                        ? 0
                                        : MediaQuery.paddingOf(
                                            this.context,
                                          ).top)
                              : videoDetailController.isExpanding ||
                                    videoDetailController.isCollapsing
                              ? animHeight
                              : videoDetailController.videoHeight,
                          width: width,
                          child: videoPlayer(
                            width,
                            !isPortrait || isFullScreen
                                ? height
                                : videoDetailController.isExpanding ||
                                      videoDetailController.isCollapsing
                                ? animHeight
                                : videoDetailController.videoHeight,
                          ),
                        );
                      },
                    ),
                    Obx(
                      () {
                        Widget toolbar() => Opacity(
                          opacity: videoDetailController.scrollRatio.value,
                          child: Container(
                            color: themeData.colorScheme.surface,
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              height: kToolbarHeight,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 42,
                                          height: 34,
                                          child: IconButton(
                                            tooltip: '返回',
                                            icon: Icon(
                                              FontAwesomeIcons.arrowLeft,
                                              size: 15,
                                              color: themeData
                                                  .colorScheme
                                                  .onSurface,
                                            ),
                                            onPressed: Get.back,
                                          ),
                                        ),
                                        SizedBox(
                                          width: 42,
                                          height: 34,
                                          child: IconButton(
                                            tooltip: '返回主页',
                                            icon: Icon(
                                              FontAwesomeIcons.house,
                                              size: 15,
                                              color: themeData
                                                  .colorScheme
                                                  .onSurface,
                                            ),
                                            onPressed: () {
                                              videoDetailController
                                                      .plPlayerController
                                                      .backToHome =
                                                  true;
                                              Get.until(
                                                (route) => route.isFirst,
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.play_arrow_rounded,
                                          color: themeData.colorScheme.primary,
                                        ),
                                        Text(
                                          '${videoDetailController.playedTime == null
                                              ? '立即'
                                              : plPlayerController!.playerStatus.status.value == PlayerStatus.completed
                                              ? '重新'
                                              : '继续'}播放',
                                          style: TextStyle(
                                            color:
                                                themeData.colorScheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child:
                                        videoDetailController.playedTime == null
                                        ? PopupMenuButton<String>(
                                            icon: Icon(
                                              size: 22,
                                              Icons.more_vert,
                                              color: themeData
                                                  .colorScheme
                                                  .onSurface,
                                            ),
                                            onSelected: (String type) async {
                                              switch (type) {
                                                case 'later':
                                                  await videoIntroController
                                                      .viewLater();
                                                  break;
                                                case 'report':
                                                  if (!Accounts.main.isLogin) {
                                                    SmartDialog.showToast(
                                                      '账号未登录',
                                                    );
                                                  } else {
                                                    PageUtils.reportVideo(
                                                      videoDetailController
                                                          .oid
                                                          .value,
                                                    );
                                                  }
                                                  break;
                                                case 'note':
                                                  videoDetailController
                                                      .showNoteList(context);
                                                  break;
                                                case 'savePic':
                                                  ImageUtil.downloadImg(
                                                    context,
                                                    [
                                                      videoDetailController
                                                          .cover
                                                          .value,
                                                    ],
                                                  );
                                                  break;
                                              }
                                            },
                                            itemBuilder:
                                                (
                                                  BuildContext context,
                                                ) => <PopupMenuEntry<String>>[
                                                  const PopupMenuItem<String>(
                                                    value: 'later',
                                                    child: Text('稍后再看'),
                                                  ),
                                                  if (videoDetailController
                                                          .epId ==
                                                      null)
                                                    const PopupMenuItem<String>(
                                                      value: 'note',
                                                      child: Text('查看笔记'),
                                                    ),
                                                  if (videoDetailController
                                                      .cover
                                                      .value
                                                      .isNotEmpty)
                                                    const PopupMenuItem<String>(
                                                      value: 'savePic',
                                                      child: Text('保存封面'),
                                                    ),
                                                  const PopupMenuItem<String>(
                                                    value: 'report',
                                                    child: Text('举报'),
                                                  ),
                                                ],
                                          )
                                        : SizedBox(
                                            width: 42,
                                            height: 34,
                                            child: IconButton(
                                              tooltip: "更多设置",
                                              style: ButtonStyle(
                                                padding:
                                                    WidgetStateProperty.all(
                                                      EdgeInsets.zero,
                                                    ),
                                              ),
                                              onPressed: () =>
                                                  videoDetailController
                                                      .headerCtrKey
                                                      .currentState
                                                      ?.showSettingSheet(),
                                              icon: Icon(
                                                Icons.more_vert_outlined,
                                                size: 19,
                                                color: themeData
                                                    .colorScheme
                                                    .onSurface,
                                              ),
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                        return videoDetailController.scrollRatio.value == 0 ||
                                videoDetailController.scrollCtr.offset == 0 ||
                                !isPortrait
                            ? const SizedBox.shrink()
                            : Positioned.fill(
                                bottom: -2,
                                child: GestureDetector(
                                  onTap: () async {
                                    if (videoDetailController.isQuerying) {
                                      if (kDebugMode) {
                                        debugPrint('handlePlay: querying');
                                      }
                                      return;
                                    }
                                    if (videoDetailController.videoUrl ==
                                            null ||
                                        videoDetailController.audioUrl ==
                                            null) {
                                      if (kDebugMode) {
                                        debugPrint(
                                          'handlePlay: videoUrl/audioUrl not initialized',
                                        );
                                      }
                                      videoDetailController.queryVideoUrl();
                                      return;
                                    }
                                    videoDetailController.scrollRatio.value = 0;
                                    if (plPlayerController == null ||
                                        videoDetailController.playedTime ==
                                            null) {
                                      handlePlay();
                                    } else {
                                      if (plPlayerController!
                                          .videoPlayerController!
                                          .state
                                          .completed) {
                                        await plPlayerController!
                                            .videoPlayerController!
                                            .seek(Duration.zero);
                                        plPlayerController!
                                            .videoPlayerController!
                                            .play();
                                      } else {
                                        plPlayerController!
                                            .videoPlayerController!
                                            .playOrPause();
                                      }
                                    }
                                  },
                                  behavior: HitTestBehavior.opaque,
                                  child: toolbar(),
                                ),
                              );
                      },
                    ),
                  ],
                ),
              ),
            ];
          },
          body: Scaffold(
            key: videoDetailController.childKey,
            resizeToAvoidBottomInset: false,
            backgroundColor: Colors.transparent,
            body: Column(
              children: [
                buildTabbar(
                  showReply: videoDetailController.showReply,
                  onTap: videoDetailController.animToTop,
                ),
                Expanded(
                  child: videoTabBarView(
                    controller: videoDetailController.tabCtr,
                    children: [
                      videoIntro(true, false),
                      if (videoDetailController.showReply)
                        videoReplyPanel(false),
                      if (_shouldShowSeasonPanel) seasonPanel,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget get childWhenDisabledAlmostSquareInner => Obx(
    () {
      final size = MediaQuery.sizeOf(context);
      final double width = size.width;
      final double height = size.height;
      final padding = MediaQuery.paddingOf(context);
      if (enableVerticalExpand &&
          videoDetailController.direction.value == 'vertical') {
        final double videoHeight =
            height - (removeSafeArea ? 0 : padding.vertical);
        final double videoWidth = videoHeight * 9 / 16;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: videoHeight,
              width: isFullScreen ? width : videoWidth,
              child: videoPlayer(videoWidth, videoHeight),
            ),
            Expanded(
              child: Scaffold(
                key: videoDetailController.childKey,
                resizeToAvoidBottomInset: false,
                backgroundColor: Colors.transparent,
                body: Column(
                  children: [
                    buildTabbar(showReply: videoDetailController.showReply),
                    Expanded(
                      child: videoTabBarView(
                        controller: videoDetailController.tabCtr,
                        children: [
                          videoIntro(),
                          if (videoDetailController.showReply)
                            videoReplyPanel(),
                          if (_shouldShowSeasonPanel) seasonPanel,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }
      final double videoHeight = height / 2.5;
      return Column(
        children: [
          SizedBox(
            width: width,
            height: isFullScreen
                ? height - (removeSafeArea ? 0 : padding.vertical)
                : videoHeight,
            child: videoPlayer(width, videoHeight),
          ),
          Expanded(
            child: Scaffold(
              key: videoDetailController.childKey,
              resizeToAvoidBottomInset: false,
              backgroundColor: Colors.transparent,
              body: Column(
                children: [
                  buildTabbar(
                    needIndicator: false,
                    showReply: videoDetailController.showReply,
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: videoIntro()),
                        if (videoDetailController.showReply)
                          Expanded(child: videoReplyPanel()),
                        if (_shouldShowSeasonPanel)
                          Expanded(child: seasonPanel),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget get childWhenDisabledLandscapeInner => Obx(
    () {
      final size = MediaQuery.sizeOf(context);
      final double width = size.width;
      final double height = size.height;
      final padding = MediaQuery.paddingOf(context);
      if (enableVerticalExpand &&
          videoDetailController.direction.value == 'vertical') {
        final double videoHeight = height - (removeSafeArea ? 0 : padding.top);
        final double videoWidth = videoHeight * 9 / 16;
        return Row(
          children: [
            Expanded(
              child: isFullScreen ? const SizedBox.shrink() : videoIntro(),
            ),
            SizedBox(
              height: videoHeight,
              width: isFullScreen ? width : videoWidth,
              child: videoPlayer(videoWidth, videoHeight),
            ),
            Expanded(
              child: Scaffold(
                key: videoDetailController.childKey,
                resizeToAvoidBottomInset: false,
                backgroundColor: Colors.transparent,
                body: Column(
                  children: [
                    buildTabbar(
                      showIntro: false,
                      showReply: videoDetailController.showReply,
                    ),
                    Expanded(
                      child: videoTabBarView(
                        controller: videoDetailController.tabCtr,
                        children: [
                          if (videoDetailController.showReply)
                            videoReplyPanel(),
                          if (_shouldShowSeasonPanel) seasonPanel,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }
      double videoWidth = clampDouble(height / width * 1.08, 0.5, 0.7) * width;
      if (width >= 560) {
        videoWidth = min(videoWidth, width - 280);
      }
      final double videoHeight = videoWidth * 9 / 16;
      return Row(
        children: [
          Column(
            children: [
              SizedBox(
                width: isFullScreen ? width : videoWidth,
                height: isFullScreen ? height : videoHeight,
                child: videoPlayer(videoWidth, videoHeight),
              ),
              Offstage(
                offstage: isFullScreen,
                child: SizedBox(
                  width: videoWidth,
                  height:
                      height - videoHeight - (removeSafeArea ? 0 : padding.top),
                  child: videoIntro(false, false),
                ),
              ),
            ],
          ),
          Offstage(
            offstage: isFullScreen,
            child: SizedBox(
              width:
                  width -
                  videoWidth -
                  (removeSafeArea ? 0 : padding.horizontal),
              height: height - (removeSafeArea ? 0 : padding.top),
              child: Scaffold(
                key: videoDetailController.childKey,
                resizeToAvoidBottomInset: false,
                backgroundColor: Colors.transparent,
                body: Column(
                  children: [
                    buildTabbar(
                      introText: '相关视频',
                      showIntro:
                          videoDetailController.videoType == SearchType.video &&
                          videoDetailController
                              .plPlayerController
                              .showRelatedVideo,
                      showReply: videoDetailController.showReply,
                    ),
                    Expanded(
                      child: videoTabBarView(
                        controller: videoDetailController.tabCtr,
                        children: [
                          if (videoDetailController.videoType ==
                                  SearchType.video &&
                              videoDetailController
                                  .plPlayerController
                                  .showRelatedVideo)
                            CustomScrollView(
                              controller: _introController,
                              slivers: [
                                RelatedVideoPanel(
                                  key: relatedVideoPanelKey,
                                  heroTag: heroTag,
                                ),
                              ],
                            ),
                          if (videoDetailController.showReply)
                            videoReplyPanel(),
                          if (_shouldShowSeasonPanel) seasonPanel,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget get childWhenDisabledLandscape => Stack(
    clipBehavior: Clip.none,
    children: [
      Scaffold(
        resizeToAvoidBottomInset: false,
        key: videoDetailController.scaffoldKey,
        appBar: (removeSafeArea || isFullScreen)
            ? null
            : AppBar(
                backgroundColor: Colors.black,
                toolbarHeight: 0,
              ),
        body: SafeArea(
          left: !removeSafeArea && !isFullScreen,
          right: !removeSafeArea && !isFullScreen,
          top: !removeSafeArea && !isFullScreen,
          bottom: false,
          child: childWhenDisabledLandscapeInner,
        ),
      ),
    ],
  );

  Widget get childWhenDisabledAlmostSquare => Scaffold(
    resizeToAvoidBottomInset: false,
    key: videoDetailController.scaffoldKey,
    appBar: (removeSafeArea || isFullScreen)
        ? null
        : AppBar(
            backgroundColor: Colors.black,
            toolbarHeight: 0,
          ),
    body: SafeArea(
      left: !removeSafeArea && !isFullScreen,
      right: !removeSafeArea && !isFullScreen,
      top: !removeSafeArea && !isFullScreen,
      bottom: false,
      child: childWhenDisabledAlmostSquareInner,
    ),
  );

  Widget get childWhenEnabled => Obx(
    () => !videoDetailController.autoPlay.value
        ? const SizedBox.shrink()
        : PLVideoPlayer(
            key: Key(heroTag),
            plPlayerController: plPlayerController!,
            videoDetailController: videoDetailController,
            videoIntroController:
                videoDetailController.videoType == SearchType.video
                ? videoIntroController
                : null,
            pgcIntroController:
                videoDetailController.videoType == SearchType.media_bangumi
                ? pgcIntroController
                : null,
            headerControl: HeaderControl(
              controller: plPlayerController!,
              videoDetailCtr: videoDetailController,
              heroTag: heroTag,
            ),
            danmuWidget: pipNoDanmaku
                ? null
                : Obx(
                    () => PlDanmaku(
                      key: Key(
                        videoDetailController.danmakuCid.value.toString(),
                      ),
                      isPipMode: true,
                      cid: videoDetailController.danmakuCid.value,
                      playerController: plPlayerController!,
                    ),
                  ),
            showEpisodes: showEpisodes,
            showViewPoints: showViewPoints,
          ),
  );

  Widget get manualPlayerWidget => Obx(
    () => Visibility(
      visible: videoDetailController.isShowCover.value,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AppBar(
              primary: false,
              elevation: 0,
              scrolledUnderElevation: 0,
              foregroundColor: Colors.white,
              backgroundColor: Colors.transparent,
              automaticallyImplyLeading: false,
              title: Row(
                children: [
                  SizedBox(
                    width: 42,
                    height: 34,
                    child: IconButton(
                      tooltip: '返回',
                      icon: const Icon(
                        FontAwesomeIcons.arrowLeft,
                        size: 15,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            blurRadius: 1.5,
                            color: Colors.black,
                          ),
                        ],
                      ),
                      onPressed: Get.back,
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    height: 34,
                    child: IconButton(
                      tooltip: '返回主页',
                      icon: const Icon(
                        FontAwesomeIcons.house,
                        size: 15,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            blurRadius: 1.5,
                            color: Colors.black,
                          ),
                        ],
                      ),
                      onPressed: () {
                        videoDetailController.plPlayerController.backToHome =
                            true;
                        Get.until((route) => route.isFirst);
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(
                    size: 22,
                    Icons.more_vert,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        blurRadius: 1.5,
                        color: Colors.black,
                      ),
                    ],
                  ),
                  onSelected: (String type) async {
                    switch (type) {
                      case 'later':
                        await videoIntroController.viewLater();
                        break;
                      case 'report':
                        if (!Accounts.main.isLogin) {
                          SmartDialog.showToast('账号未登录');
                        } else {
                          PageUtils.reportVideo(
                            videoDetailController.oid.value,
                          );
                        }
                        break;
                      case 'note':
                        videoDetailController.showNoteList(context);
                        break;
                      case 'savePic':
                        ImageUtil.downloadImg(
                          context,
                          [videoDetailController.cover.value],
                        );
                        break;
                    }
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                        const PopupMenuItem<String>(
                          value: 'later',
                          child: Text('稍后再看'),
                        ),
                        if (videoDetailController.epId == null)
                          const PopupMenuItem<String>(
                            value: 'note',
                            child: Text('查看笔记'),
                          ),
                        if (videoDetailController.cover.value.isNotEmpty)
                          const PopupMenuItem<String>(
                            value: 'savePic',
                            child: Text('保存封面'),
                          ),
                        const PopupMenuItem<String>(
                          value: 'report',
                          child: Text('举报'),
                        ),
                      ],
                ),
              ],
            ),
          ),
          Positioned(
            right: 12,
            bottom: 10,
            child: IconButton(
              tooltip: '播放',
              onPressed: handlePlay,
              icon: Image.asset(
                'assets/images/play.png',
                width: 60,
                height: 60,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget get plPlayer => Obx(
    key: videoPlayerKey,
    () => videoDetailController.videoState.value is! Success
        ? const SizedBox.shrink()
        : !videoDetailController.autoPlay.value ||
              plPlayerController?.videoController == null
        ? const SizedBox.shrink()
        : PLVideoPlayer(
            key: Key(heroTag),
            plPlayerController: plPlayerController!,
            videoDetailController: videoDetailController,
            videoIntroController:
                videoDetailController.videoType == SearchType.video
                ? videoIntroController
                : null,
            pgcIntroController:
                videoDetailController.videoType == SearchType.media_bangumi
                ? pgcIntroController
                : null,
            headerControl: HeaderControl(
              key: videoDetailController.headerCtrKey,
              controller: videoDetailController.plPlayerController,
              videoDetailCtr: videoDetailController,
              heroTag: heroTag,
            ),
            danmuWidget: Obx(
              () => PlDanmaku(
                key: Key(videoDetailController.danmakuCid.value.toString()),
                cid: videoDetailController.danmakuCid.value,
                playerController: plPlayerController!,
              ),
            ),
            showEpisodes: showEpisodes,
            showViewPoints: showViewPoints,
          ),
  );

  Widget autoChoose(Widget childWhenDisabled) {
    if (Platform.isAndroid) {
      return Floating().isPipMode ? childWhenEnabled : childWhenDisabled;
    }
    return childWhenDisabled;
  }

  late ThemeData themeData;

  Widget get child {
    if (!videoDetailController.horizontalScreen) {
      return autoChoose(childWhenDisabled);
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth > constraints.maxHeight * 1.25) {
          return autoChoose(childWhenDisabledLandscape);
        } else if (constraints.maxWidth * (9 / 16) <
            (2 / 5) * constraints.maxHeight) {
          return autoChoose(childWhenDisabled);
        } else {
          return autoChoose(childWhenDisabledAlmostSquare);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return videoDetailController.plPlayerController.darkVideoPage
        ? Theme(data: themeData, child: child)
        : child;
  }

  Widget buildTabbar({
    bool needIndicator = true,
    String introText = '简介',
    bool showIntro = true,
    bool showReply = true,
    VoidCallback? onTap,
  }) {
    List<String> tabs = [
      if (showIntro) introText,
      if (showReply) '评论',
      if (_shouldShowSeasonPanel) '播放列表',
    ];
    if (videoDetailController.tabCtr.length != tabs.length) {
      videoDetailController.tabCtr.dispose();
      videoDetailController.tabCtr = TabController(
        vsync: this,
        length: tabs.length,
        initialIndex: tabs.isEmpty
            ? 0
            : videoDetailController.tabCtr.index.clamp(0, tabs.length - 1),
      );
    }

    Widget tabbar() => TabBar(
      labelColor: !needIndicator || tabs.length == 1
          ? themeData.colorScheme.onSurface
          : null,
      indicator: !needIndicator || tabs.length == 1
          ? const BoxDecoration()
          : null,
      padding: EdgeInsets.zero,
      controller: videoDetailController.tabCtr,
      labelStyle:
          TabBarTheme.of(context).labelStyle?.copyWith(fontSize: 13) ??
          const TextStyle(fontSize: 13),
      labelPadding: const EdgeInsets.symmetric(horizontal: 10.0),
      dividerColor: Colors.transparent,
      dividerHeight: 0,
      onTap: (value) {
        void animToTop() {
          if (onTap != null) {
            onTap();
            return;
          }
          String text = tabs[value];
          if (text == '简介' || text == '相关视频') {
            _introController.animToTop();
          } else if (text.startsWith('评论')) {
            _videoReplyController.animateToTop();
          }
        }

        if (!needIndicator || tabs.length == 1) {
          animToTop();
        } else if (!videoDetailController.tabCtr.indexIsChanging) {
          animToTop();
        }
      },
      tabs: tabs.map((text) {
        if (text == '评论') {
          return Tab(
            text:
                '评论${_videoReplyController.count.value == -1 ? '' : ' ${NumUtil.numFormat(_videoReplyController.count.value)}'}',
          );
        } else {
          return Tab(text: text);
        }
      }).toList(),
    );

    return Container(
      width: double.infinity,
      height: 45,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            width: 1,
            color: themeData.dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          if (tabs.isEmpty)
            const Spacer()
          else
            Flexible(
              flex: tabs.length == 3 ? 2 : 1,
              child: showReply ? Obx(() => tabbar()) : tabbar(),
            ),
          Flexible(
            flex: 1,
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    height: 32,
                    child: TextButton(
                      style: ButtonStyle(
                        padding: WidgetStateProperty.all(EdgeInsets.zero),
                      ),
                      onPressed: videoDetailController.showShootDanmakuSheet,
                      child: Text(
                        '发弹幕',
                        style: TextStyle(
                          fontSize: 12,
                          color: themeData.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: Obx(
                      () {
                        final enableShowDanmaku = videoDetailController
                            .plPlayerController
                            .enableShowDanmaku
                            .value;
                        return IconButton(
                          onPressed: () {
                            final newVal = !enableShowDanmaku;
                            videoDetailController
                                    .plPlayerController
                                    .enableShowDanmaku
                                    .value =
                                newVal;
                            GStorage.setting.put(
                              SettingBoxKey.enableShowDanmaku,
                              newVal,
                            );
                          },
                          icon: Icon(
                            size: 22,
                            enableShowDanmaku
                                ? CustomIcon.dm_on
                                : CustomIcon.dm_off,
                            color: enableShowDanmaku
                                ? themeData.colorScheme.secondary
                                : themeData.colorScheme.outline,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget videoPlayer(double videoWidth, double videoHeight) {
    return PopScope(
      canPop:
          !isFullScreen &&
          (videoDetailController.horizontalScreen ||
              MediaQuery.orientationOf(context) == Orientation.portrait),
      onPopInvokedWithResult: _onPopInvokedWithResult,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.black)),

          if (isShowing) plPlayer,

          if (!videoDetailController.autoPlay.value) ...[
            Obx(
              () => videoDetailController.isShowCover.value
                  ? Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: handlePlay,
                        child: Obx(
                          () => CachedNetworkImage(
                            imageUrl:
                                videoDetailController.cover.value.http2https,
                            width: videoWidth,
                            height: videoHeight,
                            fit: BoxFit.cover,
                            fadeOutDuration: const Duration(milliseconds: 120),
                            fadeInDuration: const Duration(milliseconds: 120),
                            memCacheWidth: videoWidth.cacheSize(context),
                            placeholder: (context, url) => Center(
                              child: Image.asset('assets/images/loading.png'),
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            manualPlayerWidget,
          ],

          if (videoDetailController.plPlayerController.enableSponsorBlock ||
              videoDetailController.continuePlayingPart)
            Positioned(
              left: 16,
              bottom: isFullScreen ? max(75, Get.height * 0.25) : 75,
              child: SizedBox(
                width: MediaQuery.textScalerOf(context).scale(120),
                child: AnimatedList(
                  padding: EdgeInsets.zero,
                  key: videoDetailController.listKey,
                  reverse: true,
                  shrinkWrap: true,
                  initialItemCount: videoDetailController.listData.length,
                  itemBuilder: (context, index, animation) {
                    return videoDetailController.buildItem(
                      videoDetailController.listData[index],
                      animation,
                    );
                  },
                ),
              ),
            ),

          // for debug
          // Positioned(
          //   right: 16,
          //   bottom: 75,
          //   child: FilledButton.tonal(
          //     onPressed: () {
          //       videoDetailController.onAddItem(
          //         SegmentModel(
          //           UUID: '',
          //           segmentType: SegmentType.sponsor,
          //           segment: Pair(first: 0, second: 0),
          //           skipType: SkipType.alwaysSkip,
          //         ),
          //       );
          //     },
          //     child: Text('skip'),
          //   ),
          // ),
          // Positioned(
          //   right: 16,
          //   bottom: 120,
          //   child: FilledButton.tonal(
          //     onPressed: () {
          //       videoDetailController.onAddItem(2);
          //     },
          //     child: Text('index'),
          //   ),
          // ),
          Obx(
            () {
              if (videoDetailController.showSteinEdgeInfo.value) {
                try {
                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: plPlayerController?.showControls.value == true
                            ? 75
                            : 16,
                      ),
                      child: Wrap(
                        spacing: 25,
                        runSpacing: 10,
                        children: videoDetailController
                            .steinEdgeInfo!
                            .edges!
                            .questions!
                            .first
                            .choices!
                            .map((item) {
                              return FilledButton.tonal(
                                style: FilledButton.styleFrom(
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(6),
                                    ),
                                  ),
                                  backgroundColor: themeData
                                      .colorScheme
                                      .secondaryContainer
                                      .withValues(alpha: 0.8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 15,
                                    vertical: 10,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () {
                                  videoIntroController.changeSeasonOrbangu(
                                    null,
                                    videoDetailController.bvid,
                                    item.cid,
                                    IdUtils.bv2av(videoDetailController.bvid),
                                    null,
                                    true,
                                  );
                                  videoDetailController.getSteinEdgeInfo(
                                    item.id,
                                  );
                                },
                                child: Text(item.option!),
                              );
                            })
                            .toList(),
                      ),
                    ),
                  );
                } catch (e) {
                  if (kDebugMode) debugPrint('build stein edges: $e');
                  return const SizedBox.shrink();
                }
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  Widget videoIntro([bool needRelated = true, bool needCtr = true]) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    Widget introPanel() => CustomScrollView(
      key: const PageStorageKey<String>('简介'),
      controller: needCtr ? _introController : null,
      physics: !needCtr
          ? const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics())
          : null,
      slivers: [
        if (videoDetailController.videoType == SearchType.video) ...[
          VideoIntroPanel(
            key: ugcPanelKey,
            heroTag: heroTag,
            showAiBottomSheet: showAiBottomSheet,
            showEpisodes: showEpisodes,
            onShowMemberPage: onShowMemberPage,
          ),
          if (needRelated &&
              videoDetailController.plPlayerController.showRelatedVideo) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: StyleString.safeSpace),
                child: Divider(
                  height: 1,
                  indent: 12,
                  endIndent: 12,
                  color: themeData.colorScheme.outline.withValues(alpha: 0.08),
                ),
              ),
            ),
            RelatedVideoPanel(key: relatedVideoPanelKey, heroTag: heroTag),
          ] else
            SliverToBoxAdapter(
              child: SizedBox(
                height: bottom + StyleString.safeSpace,
              ),
            ),
        ] else if (videoDetailController.videoType == SearchType.media_bangumi)
          Obx(
            () => PgcIntroPage(
              key: pgcPanelKey,
              heroTag: heroTag,
              cid: videoDetailController.cid.value,
              showEpisodes: showEpisodes,
              showIntroDetail: showIntroDetail,
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(
            height:
                bottom +
                (videoDetailController.isPlayAll &&
                        MediaQuery.orientationOf(context) ==
                            Orientation.landscape
                    ? 75
                    : 0),
          ),
        ),
      ],
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        introPanel(),
        if (videoDetailController.isPlayAll)
          Positioned(
            left: 12,
            right: 12,
            bottom: bottom + 12,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => videoDetailController.showMediaListPanel(context),
                borderRadius: const BorderRadius.all(Radius.circular(14)),
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: themeData.colorScheme.secondaryContainer.withValues(
                      alpha: 0.95,
                    ),
                    borderRadius: const BorderRadius.all(Radius.circular(14)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.playlist_play, size: 24),
                      const SizedBox(width: 10),
                      Text(
                        videoDetailController.watchLaterTitle,
                        style: TextStyle(
                          color: themeData.colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.keyboard_arrow_up_rounded, size: 26),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }

  Widget get seasonPanel {
    final videoDetail = videoIntroController.videoDetail.value;
    return Column(
      children: [
        if ((videoDetail.pages?.length ?? 0) > 1)
          if (videoDetail.ugcSeason != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: PagesPanel(
                heroTag: heroTag,
                videoIntroController: videoIntroController,
                bvid: videoIntroController.bvid,
                showEpisodes: showEpisodes,
              ),
            )
          else
            Expanded(
              child: Obx(
                () => EpisodePanel(
                  heroTag: heroTag,
                  enableSlide: false,
                  videoIntroController: videoIntroController,
                  type: EpisodeType.part,
                  list: [videoDetail.pages!],
                  cover: videoDetailController.cover.value,
                  bvid: videoDetailController.bvid,
                  aid: IdUtils.bv2av(videoDetailController.bvid),
                  cid: videoDetailController.cid.value,
                  isReversed: videoDetail.isPageReversed,
                  changeFucCall:
                      videoDetailController.videoType ==
                          SearchType.media_bangumi
                      ? pgcIntroController.changeSeasonOrbangu
                      : videoIntroController.changeSeasonOrbangu,
                  showTitle: false,
                  isSupportReverse:
                      videoDetailController.videoType !=
                      SearchType.media_bangumi,
                  onReverse: () => onReversePlay(
                    bvid: videoDetailController.bvid,
                    aid: IdUtils.bv2av(videoDetailController.bvid),
                    isSeason: false,
                  ),
                ),
              ),
            ),
        if (videoDetail.ugcSeason != null) ...[
          if ((videoDetail.pages?.length ?? 0) > 1) ...[
            const SizedBox(height: 8),
            Divider(
              height: 1,
              color: themeData.colorScheme.outline.withValues(alpha: 0.1),
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SeasonPanel(
              heroTag: heroTag,
              onTap: false,
              changeFuc: videoIntroController.changeSeasonOrbangu,
              showEpisodes: showEpisodes,
              videoIntroController: videoIntroController,
            ),
          ),
          Expanded(
            child: Obx(
              () => EpisodePanel(
                heroTag: heroTag,
                enableSlide: false,
                videoIntroController: videoIntroController,
                type: EpisodeType.season,
                initialTabIndex: videoDetailController.seasonIndex.value,
                cover: videoDetailController.cover.value,
                seasonId: videoDetail.ugcSeason!.id,
                list: videoDetail.ugcSeason!.sections!,
                bvid: videoDetailController.bvid,
                aid: IdUtils.bv2av(videoDetailController.bvid),
                cid: videoDetailController.seasonCid ?? 0,
                isReversed: videoIntroController
                    .videoDetail
                    .value
                    .ugcSeason!
                    .sections![videoDetailController.seasonIndex.value]
                    .isReversed,
                changeFucCall:
                    videoDetailController.videoType == SearchType.media_bangumi
                    ? pgcIntroController.changeSeasonOrbangu
                    : videoIntroController.changeSeasonOrbangu,
                showTitle: false,
                isSupportReverse:
                    videoDetailController.videoType != SearchType.media_bangumi,
                onReverse: () => onReversePlay(
                  bvid: videoDetailController.bvid,
                  aid: IdUtils.bv2av(videoDetailController.bvid),
                  isSeason: true,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget videoReplyPanel([bool needCtr = true]) => Obx(
    () => VideoReplyPanel(
      key: videoReplyPanelKey,
      needController: needCtr,
      bvid: videoDetailController.bvid,
      oid: videoDetailController.oid.value,
      heroTag: heroTag,
      replyReply: replyReply,
      onViewImage: videoDetailController.onViewImage,
      onDismissed: videoDetailController.onDismissed,
      callback: _horizontalPreview
          ? (imgList, index) {
              final ctr = AnimationController(
                vsync: this,
                duration: const Duration(milliseconds: 200),
              )..forward();
              PageUtils.onHorizontalPreview(
                videoDetailController.childKey,
                AnimationController(
                  vsync: this,
                  duration: Duration.zero,
                ),
                ctr,
                imgList,
                index,
                (value) async {
                  if (value == false) {
                    await ctr.reverse();
                  }
                  try {
                    ctr.dispose();
                  } catch (_) {}
                  if (value == false) {
                    Get.back();
                  }
                },
              );
            }
          : null,
    ),
  );

  // 展示二级回复
  void replyReply(ReplyInfo replyItem, int? id) {
    EasyThrottle.throttle('replyReply', const Duration(milliseconds: 500), () {
      int oid = replyItem.oid.toInt();
      int rpid = replyItem.id.toInt();
      videoDetailController.childKey.currentState?.showBottomSheet(
        backgroundColor: Colors.transparent,
        (context) => VideoReplyReplyPanel(
          id: id,
          oid: oid,
          rpid: rpid,
          firstFloor: replyItem,
          replyType: 1,
          isVideoDetail: true,
          onViewImage: videoDetailController.onViewImage,
          onDismissed: videoDetailController.onDismissed,
        ),
      );
    });
  }

  // ai总结
  void showAiBottomSheet() {
    videoDetailController.childKey.currentState?.showBottomSheet(
      backgroundColor: Colors.transparent,
      (context) =>
          AiConclusionPanel(item: videoIntroController.aiConclusionResult!),
    );
  }

  void showIntroDetail(
    PgcInfoModel videoDetail,
    List<VideoTagItem>? videoTags,
  ) {
    videoDetailController.childKey.currentState?.showBottomSheet(
      backgroundColor: Colors.transparent,
      (context) => PgcIntroPanel(
        item: videoDetail,
        videoTags: videoTags,
      ),
    );
  }

  void showEpisodes([int? index, season, episodes, bvid, aid, cid]) {
    if (bvid == null) {
      videoDetailController.showMediaListPanel(context);
      return;
    }
    Widget listSheetContent([bool? enableSlide]) => EpisodePanel(
      heroTag: heroTag,
      videoIntroController: videoIntroController,
      type: season != null
          ? EpisodeType.season
          : episodes is List<Part>
          ? EpisodeType.part
          : EpisodeType.pgc,
      cover: videoDetailController.cover.value,
      enableSlide: enableSlide,
      initialTabIndex: index ?? 0,
      bvid: bvid,
      aid: aid,
      cid: cid,
      seasonId: season?.id,
      list: season != null ? season.sections : [episodes],
      isReversed: videoDetailController.videoType == SearchType.media_bangumi
          ? null
          : season != null
          ? videoIntroController
                .videoDetail
                .value
                .ugcSeason!
                .sections![videoDetailController.seasonIndex.value]
                .isReversed
          : videoIntroController.videoDetail.value.isPageReversed,
      isSupportReverse:
          videoDetailController.videoType != SearchType.media_bangumi,
      changeFucCall: videoDetailController.videoType == SearchType.media_bangumi
          ? pgcIntroController.changeSeasonOrbangu
          : videoIntroController.changeSeasonOrbangu,
      onClose: Get.back,
      onReverse: () {
        Get.back();
        onReversePlay(
          bvid: bvid,
          aid: aid,
          isSeason: season != null,
        );
      },
    );
    if (isFullScreen || videoDetailController.showVideoSheet) {
      PageUtils.showVideoBottomSheet(
        context,
        isFullScreen: () => isFullScreen,
        child: videoDetailController.plPlayerController.darkVideoPage
            ? Theme(
                data: themeData,
                child: listSheetContent(false),
              )
            : listSheetContent(false),
      );
    } else {
      videoDetailController.childKey.currentState?.showBottomSheet(
        backgroundColor: Colors.transparent,
        (context) => listSheetContent(),
      );
    }
  }

  void onReversePlay({
    required dynamic bvid,
    required dynamic aid,
    required bool isSeason,
  }) {
    if (isSeason && videoDetailController.isPlayAll) {
      SmartDialog.showToast('当前为播放全部，合集不支持倒序');
      return;
    }

    void changeEpisode(episode) {
      videoIntroController.changeSeasonOrbangu(
        episode is pgc.EpisodeItem ? episode.epId : null,
        episode.runtimeType.toString() == "EpisodeItem" ? episode.bvid : bvid,
        episode.cid,
        episode.runtimeType.toString() == "EpisodeItem" ? episode.aid : aid,
        episode is EpisodeItem
            ? episode.arc?.pic
            : episode is pgc.EpisodeItem
            ? episode.cover
            : null,
      );
    }

    final videoDetail = videoIntroController.videoDetail.value;
    if (isSeason) {
      // reverse season
      final item = videoDetail
          .ugcSeason!
          .sections![videoDetailController.seasonIndex.value];
      item
        ..isReversed = !item.isReversed
        ..episodes = item.episodes!.reversed.toList();

      if (!videoDetailController.plPlayerController.reverseFromFirst) {
        // keep current episode
        videoDetailController
          ..seasonIndex.refresh()
          ..cid.refresh();
      } else {
        // switch to first episode
        var episode = videoIntroController
            .videoDetail
            .value
            .ugcSeason!
            .sections![videoDetailController.seasonIndex.value]
            .episodes!
            .first;
        if (episode.cid != videoDetailController.cid.value) {
          changeEpisode(episode);
          videoDetailController.seasonCid = episode.cid;
        } else {
          videoDetailController
            ..seasonIndex.refresh()
            ..cid.refresh();
        }
      }
    } else {
      // reverse part
      videoDetail
        ..isPageReversed = !videoDetail.isPageReversed
        ..pages = videoDetail.pages!.reversed.toList();
      if (!videoDetailController.plPlayerController.reverseFromFirst) {
        // keep current episode
        videoDetailController.cid.refresh();
      } else {
        // switch to first episode
        var episode = videoDetail.pages!.first;
        if (episode.cid != videoDetailController.cid.value) {
          changeEpisode(episode);
        } else {
          videoDetailController.cid.refresh();
        }
      }
    }
  }

  void showViewPoints() {
    if (isFullScreen || videoDetailController.showVideoSheet) {
      PageUtils.showVideoBottomSheet(
        context,
        isFullScreen: () => isFullScreen,
        child: videoDetailController.plPlayerController.darkVideoPage
            ? Theme(
                data: themeData,
                child: ViewPointsPage(
                  enableSlide: false,
                  videoDetailController: videoDetailController,
                  plPlayerController: plPlayerController,
                ),
              )
            : ViewPointsPage(
                enableSlide: false,
                videoDetailController: videoDetailController,
                plPlayerController: plPlayerController,
              ),
      );
    } else {
      videoDetailController.childKey.currentState?.showBottomSheet(
        backgroundColor: Colors.transparent,
        (context) => ViewPointsPage(
          videoDetailController: videoDetailController,
          plPlayerController: plPlayerController,
        ),
      );
    }
  }

  void _onPopInvokedWithResult(bool didPop, result) {
    if (plPlayerController?.controlsLock.value == true) {
      plPlayerController?.onLockControl(false);
      return;
    }
    if (isFullScreen) {
      plPlayerController!.triggerFullScreen(status: false);
    }
    if (MediaQuery.orientationOf(context) == Orientation.landscape &&
        !videoDetailController.horizontalScreen) {
      verticalScreenForTwoSeconds();
    }
  }

  void onShowMemberPage(int? mid) {
    videoDetailController.childKey.currentState?.showBottomSheet(
      shape: const RoundedRectangleBorder(),
      (context) {
        return HorizontalMemberPage(
          mid: mid,
          videoDetailController: videoDetailController,
          videoIntroController: videoIntroController,
        );
      },
    );
  }
}
