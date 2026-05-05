import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  final String friendUid;
  final String friendUsername;

  const ChatScreen({
    super.key,
    required this.friendUid,
    required this.friendUsername,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}
//Controls the text input where user types there message
class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
//prevents duplicate sends
  bool _sending = false;

  String get _myUid => FirebaseAuth.instance.currentUser!.uid;
//gets both users and friends uid and makes them into 1 uid chat
  String get _conversationId {
    final ids = [_myUid, widget.friendUid]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  DocumentReference<Map<String, dynamic>> get _conversationRef =>
      FirebaseFirestore.instance.collection('conversations').doc(_conversationId);

  CollectionReference<Map<String, dynamic>> get _messagesRef =>
      _conversationRef.collection('messages');
//Writes a message to conversations/{conversationID}/messages, creates chat_message notification for the friend
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);

    try {
      final convoSnap = await _conversationRef.get();

      if (!convoSnap.exists) {
        await _conversationRef.set({
          'participants': [_myUid, widget.friendUid],
          'lastMessage': text,
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastMessageSenderId': _myUid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _conversationRef.update({
          'lastMessage': text,
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastMessageSenderId': _myUid,
        });
      }

      await _messagesRef.add({
        'senderId': _myUid,
        'text': text,
        'sentAt': FieldValue.serverTimestamp(),
      });

      final myUserDoc =
      await FirebaseFirestore.instance.collection('users').doc(_myUid).get();
      final myUsername = (myUserDoc.data()?['username'] ?? 'Unknown').toString();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.friendUid)
          .collection('notifications')
          .add({
        'type': 'chat_message',
        'fromUid': _myUid,
        'fromUsername': myUsername,
        'status': 'pending',
        'messageText': text.length > 120 ? '${text.substring(0, 120)}...' : text,
        'conversationId': _conversationId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _messageController.clear();

      await Future.delayed(const Duration(milliseconds: 100));
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: ${e.message ?? e.code}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
//time formatter
  String _fmtTime(dynamic ts) {
    if (ts is! Timestamp) return '';
    final dt = ts.toDate().toLocal();
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
//Dispose the text controller and scroll controller
  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
//Creates the ui
  @override
  Widget build(BuildContext context) {
    final messagesQuery = _messagesRef.orderBy('sentAt', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.friendUsername),
      ),
      body: Column(
        children: [
          Expanded(
            //Flutter listening to firestore in realtime with stream to read messages
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: messagesQuery.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data?.docs ?? [];

                if (docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No messages yet.\nStart the conversation.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data();
                    final senderId = (data['senderId'] ?? '').toString();
                    final text = (data['text'] ?? '').toString();
                    final sentAt = data['sentAt'];

                    final isMe = senderId == _myUid;

                    return Align(
                      alignment:
                      isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.74,
                        ),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              text,
                              style: TextStyle(
                                color: isMe ? Colors.white : Colors.black87,
                                fontSize: 14,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _fmtTime(sentAt),
                              style: TextStyle(
                                color:
                                isMe ? Colors.white70 : Colors.black54,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _sending ? null : _sendMessage,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(60, 54),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: _sending
                        ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}