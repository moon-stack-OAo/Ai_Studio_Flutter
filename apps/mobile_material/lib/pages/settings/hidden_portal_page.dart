import 'dart:async';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 隐藏入口内嵌地址（设置「实验室」）。
const String kHiddenPortalUrl = 'https://pubg.livancen.top/';

/// 设置 Tab 内容：内嵌 WebView，无独立路由标题。
class HiddenPortalPage extends StatefulWidget {
  const HiddenPortalPage({super.key});

  @override
  State<HiddenPortalPage> createState() => _HiddenPortalPageState();
}

class _HiddenPortalPageState extends State<HiddenPortalPage> {
  WebViewController? _controller;
  String? _error;
  var _engineReady = false;
  var _pageLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_init());
    });
  }

  Future<void> _init() async {
    final bg = materialTokensOf(context).canvas;
    try {
      assertSafeHttpUrl(Uri.parse(kHiddenPortalUrl));
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(bg)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              if (!mounted) return;
              setState(() => _pageLoaded = true);
            },
            onWebResourceError: (error) {
              if (!mounted) return;
              setState(() {
                _error = error.description;
                _pageLoaded = true;
              });
            },
          ),
        );
      await controller.loadRequest(Uri.parse(kHiddenPortalUrl));
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _engineReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is UrlSafetyException ? e.message : '页面加载失败：$e';
        _pageLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    return ColoredBox(
      color: tokens.canvas,
      child: _buildBody(tokens),
    );
  }

  Widget _buildBody(MaterialTokens tokens) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: tokens.inkSecondary),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_engineReady && _controller != null)
          WebViewWidget(controller: _controller!),
        if (!_pageLoaded)
          ColoredBox(
            color: tokens.canvas,
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}
