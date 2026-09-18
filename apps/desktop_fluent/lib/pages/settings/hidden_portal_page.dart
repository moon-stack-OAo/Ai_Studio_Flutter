import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart' as win;

/// 隐藏入口内嵌地址（设置「实验室」）。
const String kHiddenPortalUrl = 'https://pubg.livancen.top/';

/// 设置分类页：内嵌 WebView，无独立路由标题。
class HiddenPortalPage extends StatefulWidget {
  const HiddenPortalPage({super.key});

  @override
  State<HiddenPortalPage> createState() => _HiddenPortalPageState();
}

class _HiddenPortalPageState extends State<HiddenPortalPage> {
  WebViewController? _stdController;
  win.WebviewController? _winController;
  StreamSubscription<win.LoadingState>? _winLoadingSub;
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
    final bg = fluentTokensOf(context).canvas;
    try {
      assertSafeHttpUrl(Uri.parse(kHiddenPortalUrl));
      if (Platform.isWindows) {
        final controller = win.WebviewController();
        await controller.initialize();
        await controller.setBackgroundColor(bg);
        await controller.setPopupWindowPolicy(win.WebviewPopupWindowPolicy.deny);
        _winLoadingSub = controller.loadingState.listen((state) {
          if (!mounted) return;
          if (state == win.LoadingState.navigationCompleted) {
            setState(() => _pageLoaded = true);
          }
        });
        await controller.loadUrl(kHiddenPortalUrl);
        if (!mounted) {
          await _winLoadingSub?.cancel();
          await controller.dispose();
          return;
        }
        setState(() {
          _winController = controller;
          _engineReady = true;
        });
        return;
      }

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
        _stdController = controller;
        _engineReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is UrlSafetyException
            ? e.message
            : (Platform.isWindows
                ? '无法启动 WebView2，请确认已安装 Edge WebView2 Runtime。\n$e'
                : '页面加载失败：$e');
        _pageLoaded = true;
      });
    }
  }

  @override
  void dispose() {
    unawaited(_winLoadingSub?.cancel() ?? Future<void>.value());
    _winLoadingSub = null;
    final winCtrl = _winController;
    _winController = null;
    if (winCtrl != null) {
      unawaited(winCtrl.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return ColoredBox(
      color: tokens.canvas,
      child: _buildBody(tokens),
    );
  }

  Widget _buildBody(FluentTokens tokens) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: tokens.inkSecondary,
              fontFamily: tokens.fontFamily,
            ),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ?_buildWebView(),
        if (!_pageLoaded)
          ColoredBox(
            color: tokens.canvas,
            child: const Center(child: ProgressRing()),
          ),
      ],
    );
  }

  Widget? _buildWebView() {
    if (!_engineReady) return null;
    if (Platform.isWindows) {
      final controller = _winController;
      if (controller == null || !controller.value.isInitialized) return null;
      return win.Webview(controller);
    }
    final controller = _stdController;
    if (controller == null) return null;
    return WebViewWidget(controller: controller);
  }
}
