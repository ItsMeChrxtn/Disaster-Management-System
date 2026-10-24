import 'package:flutter/material.dart';

import '../../core/notifications.dart';
import '../../core/session.dart';
import '../../core/ui.dart';
import '../alerts_screen.dart';
import '../coordination_screen.dart';
import '../facilities_screen.dart';
import '../hazards_screen.dart';
import '../history_screen.dart';
import '../municipalities_screen.dart';
import '../overview_screen.dart';
import '../profile_screen.dart';
import '../public/public_map_screen.dart';
import '../reports_screen.dart';
import '../users_screen.dart';
import '../weather_screen.dart';

class _NavItem {
  const _NavItem(this.key, this.label, this.icon, {this.roles});

  final String key;
  final String label;
  final IconData icon;

  /// null = every role.
  final Set<String>? roles;
}

/// Role-aware navigation shell (dashboard.html sidebar + ui.js top bar).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const List<_NavItem> _items = [
    _NavItem('overview', 'Overview', Icons.dashboard_outlined),
    _NavItem('weather', 'Weather monitoring', Icons.cloud_outlined),
    _NavItem('municipalities', 'Municipalities', Icons.location_city_outlined, roles: {'admin'}),
    _NavItem('coordination', 'Municipality', Icons.forum_outlined, roles: {'admin', 'subadmin'}),
    _NavItem('hazards', 'Hazard management', Icons.warning_amber_rounded, roles: {'admin', 'subadmin'}),
    _NavItem('safezones', 'Safety facilities', Icons.shield_outlined),
    _NavItem('alerts', 'Alerts', Icons.notifications_outlined),
    _NavItem('history', 'Historical disasters', Icons.history_outlined, roles: {'admin', 'resident'}),
    _NavItem('reports', 'Reports', Icons.description_outlined, roles: {'admin', 'subadmin'}),
    _NavItem('users', 'Users', Icons.people_outline, roles: {'admin'}),
    _NavItem('publicmap', 'Public map', Icons.map_outlined),
    _NavItem('profile', 'Profile & password', Icons.person_outline),
  ];

  String _view = 'overview';

  @override
  void initState() {
    super.initState();
    AlertNotifier.instance.addListener(_onAlerts);
    AlertNotifier.instance.start();
    AlertNotifier.instance.requestPermission();
    if (Session.instance.mustChangePassword) {
      _view = 'profile';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Ui.toast(context, 'Change your temporary password before continuing.', icon: 'info');
      });
    }
  }

  @override
  void dispose() {
    AlertNotifier.instance.removeListener(_onAlerts);
    AlertNotifier.instance.stop();
    super.dispose();
  }

  void _onAlerts() {
    if (!mounted) return;
    final latest = AlertNotifier.instance.latestUnseen;
    if (latest != null) {
      AlertNotifier.instance.latestUnseen = null;
      Ui.toast(context, '${str(latest, 'title')}: ${str(latest, 'message')}', icon: 'warning');
    }
    setState(() {});
  }

  List<_NavItem> get _visibleItems {
    final role = Session.instance.role;
    return _items
        .where((item) => item.roles == null || item.roles!.contains(role))
        .map((item) => item.key == 'coordination' && role == 'admin' ? const _NavItem('coordination', 'LGU coordination', Icons.forum_outlined, roles: {'admin', 'subadmin'}) : item)
        .toList();
  }

  void _open(String view) {
    setState(() => _view = view);
  }

  Future<void> _logout() async {
    if (!await Ui.confirm(context, 'Sign out of Disaster Map?', message: 'You will need to sign in again.', confirmText: 'Sign out', danger: false)) return;
    if (!mounted) return;
    await Ui.withLoading(context, 'Signing out...', () => Session.instance.logout());
  }

  Future<void> _openNotifications() async {
    final notifier = AlertNotifier.instance;
    await notifier.refresh();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => ListenableBuilder(
        listenable: notifier,
        builder: (context, _) {
          final rows = notifier.history.take(6).toList();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Notifications', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                      TextButton(
                        onPressed: () async {
                          try {
                            await notifier.markAllRead();
                            if (context.mounted) Ui.toast(context, 'Notifications marked as read');
                          } catch (e) {
                            if (context.mounted) Ui.showError(context, e.toString());
                          }
                        },
                        child: const Text('Mark all read'),
                      ),
                    ],
                  ),
                  if (rows.isEmpty) const EmptyNote('No notifications.'),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: rows
                          .map(
                            (x) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.circle, size: 10, color: isRead(x) ? Colors.transparent : Ui.red),
                              title: Text(str(x, 'title'), style: TextStyle(fontWeight: isRead(x) ? FontWeight.w500 : FontWeight.w800)),
                              subtitle: Text('${str(x, 'message')}\n${Ui.formatDateTime(x['sent_at'] ?? x['created_at'])}', maxLines: 3, overflow: TextOverflow.ellipsis),
                              onTap: () async {
                                try {
                                  await notifier.markRead(x['id'] ?? '');
                                } catch (e) {
                                  if (context.mounted) Ui.showError(context, e.toString());
                                }
                              },
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _open('alerts');
                    },
                    child: const Text('Open alert center'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body() {
    switch (_view) {
      case 'weather':
        return const WeatherScreen();
      case 'municipalities':
        return MunicipalitiesScreen(onOpenCoordination: () => _open('coordination'));
      case 'coordination':
        return const CoordinationScreen();
      case 'hazards':
        return const HazardsScreen();
      case 'safezones':
        return const FacilitiesScreen();
      case 'alerts':
        return const AlertsScreen();
      case 'history':
        return const HistoryScreen();
      case 'reports':
        return const ReportsScreen();
      case 'users':
        return const UsersScreen();
      case 'publicmap':
        return const PublicMapScreen(embedded: true);
      case 'profile':
        return const ProfileScreen();
      default:
        return OverviewScreen(onOpenView: _open);
    }
  }

  /// Primary tabs shown in the bottom bar (max 4) – the rest live under "More".
  List<_NavItem> _primaryTabs(List<_NavItem> items) {
    final keys = Session.instance.isResident ? ['overview', 'publicmap', 'safezones', 'alerts'] : ['overview', 'hazards', 'safezones', 'alerts'];
    return keys.map((k) => items.where((i) => i.key == k).firstOrNull).whereType<_NavItem>().toList();
  }

  String _tabLabel(String key) => const {'overview': 'Home', 'hazards': 'Hazards', 'safezones': 'Facilities', 'alerts': 'Alerts', 'publicmap': 'Map'}[key] ?? key;

  Widget _bottomBar(List<_NavItem> items, int unread) {
    final primary = _primaryTabs(items);
    final moreActive = !primary.any((i) => i.key == _view);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Ui.line)),
        boxShadow: [BoxShadow(color: Color(0x1A0F172A), blurRadius: 24, offset: Offset(0, -8), spreadRadius: -12)],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final item in primary) _tab(item.icon, _tabLabel(item.key), item.key == _view, () => _open(item.key), badge: item.key == 'alerts' ? unread : 0),
              _tab(Icons.grid_view_rounded, 'More', moreActive, () => _openMore(items, primary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(IconData icon, String label, bool active, VoidCallback onTap, {int badge = 0}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Badge(
              isLabelVisible: badge > 0,
              label: Text('$badge'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 44,
                height: 30,
                decoration: BoxDecoration(
                  gradient: active ? const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF0EA5E9)]) : null,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: active ? const [BoxShadow(color: Color(0x802563EB), blurRadius: 16, offset: Offset(0, 6), spreadRadius: -8)] : null,
                ),
                child: Icon(icon, size: 21, color: active ? Colors.white : Ui.slate400),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? Ui.indigo : Ui.slate500),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMore(List<_NavItem> items, List<_NavItem> primary) async {
    final session = Session.instance;
    final rest = items.where((i) => !primary.contains(i)).toList();
    final initial = session.fullname.isEmpty ? 'U' : session.fullname[0].toUpperCase();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(gradient: kNavyGradient, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.white,
                      child: Text(
                        initial,
                        style: const TextStyle(color: Ui.navy, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.fullname,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            session.isSubadmin && session.municipalityName.isNotEmpty ? '${session.roleLabel} · ${session.municipalityName}' : session.roleLabel,
                            style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 11.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                      onPressed: () {
                        Navigator.pop(context);
                        _logout();
                      },
                      icon: const Icon(Icons.logout, size: 16),
                      label: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text('More modules', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.15,
                children: rest.map((item) {
                  final active = item.key == _view;
                  return Material(
                    color: active ? Ui.primarySoft : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _open(item.key);
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: active ? const Color(0xFFC7D5FF) : Ui.line),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconTile(icon: item.icon, color: Ui.indigo, size: 36),
                            const SizedBox(height: 8),
                            Text(
                              item.label,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: active ? Ui.indigo : Ui.slate900, height: 1.2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = Session.instance;
    final items = _visibleItems;
    final current = items.firstWhere((i) => i.key == _view, orElse: () => items.first);
    final unread = AlertNotifier.instance.unreadCount;
    final initial = session.fullname.isEmpty ? 'U' : session.fullname[0].toUpperCase();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: kGradBlue),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.location_on_outlined, color: Colors.white, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    current.label,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    session.isSubadmin && session.municipalityName.isNotEmpty ? '${session.roleLabel} · ${session.municipalityName}' : session.roleLabel,
                    style: const TextStyle(fontSize: 11, color: Ui.slate500, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: _openNotifications,
            icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.notifications_outlined)),
          ),
          PopupMenuButton<String>(
            tooltip: 'User menu',
            onSelected: (value) => value == 'logout' ? _logout() : _open('profile'),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'profile', child: Text('Profile & security')),
              PopupMenuItem(
                value: 'logout',
                child: Text('Sign out', style: TextStyle(color: Ui.red)),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.only(right: 12, left: 4),
              child: CircleAvatar(
                radius: 17,
                backgroundColor: Ui.navy,
                child: Text(
                  initial,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _bottomBar(items, unread),
      body: KeyedSubtree(key: ValueKey(_view), child: _body()),
    );
  }
}
