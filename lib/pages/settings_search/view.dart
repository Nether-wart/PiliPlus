import 'dart:async';

import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/pages/setting/models/extra_settings.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/models/play_settings.dart';
import 'package:PiliPlus/pages/setting/models/privacy_settings.dart';
import 'package:PiliPlus/pages/setting/models/recommend_settings.dart';
import 'package:PiliPlus/pages/setting/models/style_settings.dart';
import 'package:PiliPlus/pages/setting/models/video_settings.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:stream_transform/stream_transform.dart';
import 'package:waterfall_flow/waterfall_flow.dart';

class SettingsSearchPage extends StatefulWidget {
  const SettingsSearchPage({super.key});

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState extends State<SettingsSearchPage> {
  final _textEditingController = TextEditingController();
  final RxList<SettingsModel> _list = <SettingsModel>[].obs;
  late final _settings = [
    ...extraSettings,
    ...privacySettings,
    ...recommendSettings,
    ...videoSettings,
    ...playSettings,
    ...styleSettings,
  ];
  late StreamController<String> _ctr;
  late StreamSubscription<String> _sub;

  @override
  void initState() {
    super.initState();
    _ctr = StreamController<String>();
    _sub = _ctr.stream
        .debounce(const Duration(milliseconds: 200), trailing: true)
        .listen((value) {
          if (value.isEmpty) {
            _list.clear();
          } else {
            value = value.toLowerCase();
            _list.value = _settings
                .where(
                  (item) =>
                      (item.title ?? item.getTitle?.call())
                          ?.toLowerCase()
                          .contains(value) ||
                      item.subtitle?.toLowerCase().contains(value) == true,
                )
                .toList();
          }
        });
  }

  @override
  void dispose() {
    _sub.cancel();
    _ctr.close();
    _textEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: () {
              if (_textEditingController.text.isNotEmpty) {
                _textEditingController.clear();
                _list.value = <SettingsModel>[];
              } else {
                Get.back();
              }
            },
            icon: const Icon(Icons.clear),
          ),
          const SizedBox(width: 10),
        ],
        title: TextField(
          autofocus: true,
          controller: _textEditingController,
          textAlignVertical: TextAlignVertical.center,
          onChanged: _ctr.add,
          decoration: const InputDecoration(
            isDense: true,
            hintText: '搜索',
            border: InputBorder.none,
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + 80,
              ),
              sliver: Obx(
                () => _list.isEmpty
                    ? const HttpError()
                    : SliverWaterfallFlow.extent(
                        maxCrossAxisExtent: Grid.smallCardWidth * 2,
                        children: [
                          ..._list.map((item) => item.widget),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
