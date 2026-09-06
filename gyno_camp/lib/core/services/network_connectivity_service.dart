import 'dart:async';

abstract class INetworkConnectivityService {
  bool get isOnline;
  Stream<bool> get onConnectivityChanged;
  Future<bool> checkConnection();
  void setOnline(bool online);
  void dispose();
}

class NetworkConnectivityService implements INetworkConnectivityService {
  bool _isOnline;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  NetworkConnectivityService({bool initialOnline = true}) : _isOnline = initialOnline;

  @override
  bool get isOnline => _isOnline;

  @override
  Stream<bool> get onConnectivityChanged => _controller.stream;

  @override
  Future<bool> checkConnection() async {
    return _isOnline;
  }

  @override
  void setOnline(bool online) {
    if (_isOnline != online) {
      _isOnline = online;
      _controller.add(_isOnline);
    }
  }

  @override
  void dispose() {
    _controller.close();
  }
}
