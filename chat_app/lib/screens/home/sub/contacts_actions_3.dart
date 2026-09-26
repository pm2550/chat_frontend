part of '../contacts_page.dart';

extension _ContactsActions3Parts on _ContactsPageState {
  Future<void> _removeContact(User contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除好友'),
        content: Text('确定删除 ${_displayName(contact)} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await _contactService.removeFriend(contact.id);
      _showSnackBar('已删除 ${_displayName(contact)}');
      await _loadContacts();
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  String _displayName(User user) {
    if (user.displayName.isNotEmpty) {
      return user.displayName;
    }
    if (user.username.isNotEmpty) {
      return user.username;
    }
    return user.email;
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
