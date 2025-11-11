import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: AuthPage(),
    );
  }
}

class AuthPage extends StatefulWidget {
  @override
  _AuthPageState createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isLogin = true;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();

  Future<void> _auth() async {
    if (!_formKey.currentState!.validate()) return;

    final url = Uri.parse(
      'http://192.168.0.169:3000/${_isLogin ? 'login' : 'register'}',
    );
    final body = _isLogin
        ? {'email': _emailController.text, 'password': _passwordController.text}
        : {
            'username': _usernameController.text,
            'email': _emailController.text,
            'password': _passwordController.text,
          };

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ConversationListPage(
              token: data['token'],
              userId: data['userId'].toString(),
              username: data['username'],
            ),
          ),
        );
      } else {
        final error = json.decode(response.body);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error['error'])));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur de connexion: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isLogin ? 'Connexion' : 'Inscription')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              if (!_isLogin)
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(labelText: 'Nom d\'utilisateur'),
                  validator: (value) =>
                      value!.isEmpty ? 'Champ obligatoire' : null,
                ),
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(labelText: 'Email'),
                validator: (value) =>
                    value!.isEmpty ? 'Champ obligatoire' : null,
              ),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: 'Mot de passe'),
                obscureText: true,
                validator: (value) =>
                    value!.isEmpty ? 'Champ obligatoire' : null,
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _auth,
                child: Text(_isLogin ? 'Se connecter' : 'S\'inscrire'),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLogin = !_isLogin;
                  });
                },
                child: Text(
                  _isLogin
                      ? 'Créer un compte'
                      : 'Déjà un compte ? Se connecter',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ConversationListPage extends StatefulWidget {
  final String token;
  final String userId;
  final String username;

  ConversationListPage({
    required this.token,
    required this.userId,
    required this.username,
  });

  @override
  _ConversationListPageState createState() => _ConversationListPageState();
}

class _ConversationListPageState extends State<ConversationListPage> {
  List<dynamic> _conversations = [];
  List<dynamic> _users = [];

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _loadUsers();
  }

  Future<void> _loadConversations() async {
    final url = Uri.parse('http://192.168.0.169:3000/conversations');

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          _conversations = json.decode(response.body);
        });
      } else {
        print('Erreur HTTP: ${response.statusCode}');
      }
    } catch (e) {
      print('Erreur chargement conversations: $e');
    }
  }

  Future<void> _loadUsers() async {
    final url = Uri.parse('http://192.168.0.169:3000/users');

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          _users = json.decode(response.body);
        });
      }
    } catch (e) {
      print('Erreur chargement utilisateurs: $e');
    }
  }

  Future<void> _createConversation(int otherUserId) async {
    final url = Uri.parse('http://192.168.0.169:3000/conversations');

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: json.encode({'otherUserId': otherUserId}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _loadConversations(); // Recharger la liste

        // Si c'est une nouvelle conversation, naviguer vers le chat
        if (!data['exists']) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatPage(
                token: widget.token,
                userId: widget.userId,
                username: widget.username,
                conversationId: data['conversationId'].toString(),
                otherUser: _getUserNameById(otherUserId),
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('Erreur création conversation: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur création conversation')));
    }
  }

  String _getUserNameById(int userId) {
    final user = _users.firstWhere(
      (user) => user['id'] == userId,
      orElse: () => null,
    );
    return user != null ? user['username'] : 'Utilisateur';
  }

  void _showUserSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Démarrer une conversation'),
        content: Container(
          width: double.maxFinite,
          height: 300,
          child: _users.isEmpty
              ? Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    return ListTile(
                      leading: CircleAvatar(child: Text(user['username'][0])),
                      title: Text(user['username']),
                      subtitle: Text(user['email']),
                      onTap: () {
                        Navigator.pop(context);
                        _createConversation(user['id']);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annuler'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Conversations'),
        // Tu peux supprimer ce bouton maintenant 👇
        // actions: [
        //   IconButton(icon: Icon(Icons.refresh), onPressed: _loadConversations),
        // ],
      ),
      body: _conversations.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.hourglass_empty, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Aucune conversation',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Appuyez sur le + pour démarrer une conversation',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadConversations, // pull-to-refresh (optionnel)
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _conversations.length,
                itemBuilder: (context, index) {
                  final conversation = _conversations[index];
                  return Card(
                    margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(conversation['other_user']?[0] ?? '?'),
                      ),
                      title: Text(
                        conversation['other_user'] ?? 'Utilisateur inconnu',
                      ),
                      subtitle: Text(
                        conversation['last_message'] ?? 'Aucun message',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _formatDate(
                              conversation['last_message_time'] ?? '',
                            ),
                          ),
                          if (conversation['last_message_time'] != null)
                            Icon(Icons.done_all, size: 16, color: Colors.blue),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatPage(
                              token: widget.token,
                              userId: widget.userId,
                              username: widget.username,
                              conversationId: conversation['id'].toString(),
                              otherUser:
                                  conversation['other_user'] ?? 'Utilisateur',
                            ),
                          ),
                        ).then((_) {
                          // 🔁 Dès qu’on revient sur cette page, recharge automatiquement
                          _loadConversations();
                        });
                      },
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showUserSelectionDialog,
        child: Icon(Icons.add),
        tooltip: 'Nouvelle conversation',
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }
}

class ChatPage extends StatefulWidget {
  final String token;
  final String userId;
  final String username;
  final String conversationId;
  final String otherUser;

  ChatPage({
    required this.token,
    required this.userId,
    required this.username,
    required this.conversationId,
    required this.otherUser,
  });

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _messageController = TextEditingController();
  final List<dynamic> _messages = [];
  late IO.Socket _socket;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _initSocket();
  }

  void _initSocket() {
    try {
      _socket = IO.io(
        'http://192.168.0.169:3000',
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .enableAutoConnect()
            .build(),
      );

      _socket.connect();

      _socket.onConnect((_) {
        print('Connecté au serveur Socket.io');
        _socket.emit('join_conversation', widget.conversationId);
      });

      _socket.on('new_message', (data) {
        print('Nouveau message reçu: $data');
        setState(() {
          _messages.add(data);
        });
        _scrollToBottom();
      });

      _socket.onError((error) {
        print('Erreur Socket: $error');
      });
    } catch (e) {
      print('Erreur initialisation socket: $e');
    }
  }

  Future<void> _loadMessages() async {
    final url = Uri.parse(
      'http://192.168.0.169:3000/messages/${widget.conversationId}',
    );

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          _messages.clear();
          _messages.addAll(json.decode(response.body));
        });
        _scrollToBottom();
      } else {
        print('Erreur HTTP: ${response.statusCode}');
      }
    } catch (e) {
      print('Erreur chargement messages: $e');
    }
  }

  void _sendMessage() {
    if (_messageController.text.isEmpty) return;

    final message = {
      'conversationId': int.parse(widget.conversationId),
      'senderId': int.parse(widget.userId),
      'content': _messageController.text,
    };
    _loadMessages();

    _socket.emit('send_message', message);
    _messageController.clear();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _socket.disconnect();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.otherUser),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.all(8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isMe = message['sender_id'].toString() == widget.userId;

                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: isMe
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.start,
                    children: [
                      if (!isMe) ...[
                        CircleAvatar(
                          radius: 16,
                          child: Text(message['sender_name']?[0] ?? '?'),
                        ),
                        SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.blue : Colors.grey[300],
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isMe)
                                Text(
                                  message['sender_name'] ?? 'Utilisateur',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.blue,
                                  ),
                                ),
                              Text(
                                message['content'] ?? '',
                                style: TextStyle(
                                  color: isMe ? Colors.white : Colors.black,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                _formatTime(message['created_at'] ?? ''),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isMe
                                      ? Colors.white70
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isMe) ...[
                        SizedBox(width: 8),
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.blue,
                          child: Text(
                            widget.username[0],
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Tapez votre message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: IconButton(
                    icon: Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }
}
