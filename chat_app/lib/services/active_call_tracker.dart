import 'package:flutter/foundation.dart';

/// 当前是否在通话中（任一平台的通话服务都会更新它）。
///
/// 切到后台时要不要断开前台连接取决于它：通话中断开会收不到对方挂断、
/// 发不出自己的挂断，所以通话期间保持连接。
class ActiveCallTracker {
  ActiveCallTracker._();

  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);
}
