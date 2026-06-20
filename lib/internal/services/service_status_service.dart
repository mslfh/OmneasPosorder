import '../../common/services/background_task_manager.dart';

class ServiceStatusService {
  final BackgroundTaskManager _backgroundTaskManager;

  ServiceStatusService({BackgroundTaskManager? backgroundTaskManager})
      : _backgroundTaskManager = backgroundTaskManager ?? BackgroundTaskManager();

  Future<ServiceStatusResult> fetchServiceStatus() async {
    return _backgroundTaskManager.checkServiceStatus();
  }
}

