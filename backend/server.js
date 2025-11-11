// backend/server.js

const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const mysql = require('mysql2');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const cors = require('cors');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
    cors: {
        origin: "*",
        methods: ["GET", "POST"]
    }
});

app.use(cors());
app.use(express.json());

// Configuration MySQL via variables d'environnement
const db = mysql.createConnection({
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
    port: process.env.DB_PORT || 3306
});

db.connect(err => {
    if (err) {
        console.error('❌ Erreur connexion MySQL:', err);
        process.exit(1); // stoppe le serveur si la DB est inaccessible
    }
    console.log('✅ Connecté à MySQL');
});

// Secret JWT depuis variable d'environnement
const JWT_SECRET = process.env.JWT_SECRET || 'default_secret';

// Middleware d'authentification
const authenticateToken = (req, res, next) => {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (!token) return res.status(401).json({ error: 'Token requis' });

    jwt.verify(token, JWT_SECRET, (err, user) => {
        if (err) return res.status(403).json({ error: 'Token invalide' });
        req.user = user;
        next();
    });
};

// --- Routes d'authentification ---

app.post('/register', async (req, res) => {
    const { username, email, password } = req.body;

    try {
        const hashedPassword = await bcrypt.hash(password, 10);

        db.query(
            'INSERT INTO users (username, email, password) VALUES (?, ?, ?)',
            [username, email, hashedPassword],
            (err, result) => {
                if (err) {
                    return res.status(400).json({ error: 'Utilisateur déjà existant' });
                }

                const token = jwt.sign({ userId: result.insertId, username }, JWT_SECRET);
                res.json({ token, userId: result.insertId, username });
            }
        );
    } catch (error) {
        res.status(500).json({ error: 'Erreur serveur' });
    }
});

app.post('/login', (req, res) => {
    const { email, password } = req.body;

    db.query(
        'SELECT * FROM users WHERE email = ?',
        [email],
        async (err, results) => {
            if (err || results.length === 0) {
                return res.status(400).json({ error: 'Utilisateur non trouvé' });
            }

            const user = results[0];
            const validPassword = await bcrypt.compare(password, user.password);

            if (!validPassword) {
                return res.status(400).json({ error: 'Mot de passe incorrect' });
            }

            const token = jwt.sign({ userId: user.id, username: user.username }, JWT_SECRET);
            res.json({ token, userId: user.id, username: user.username });
        }
    );
});

// --- Utilisateurs ---
app.get('/users', authenticateToken, (req, res) => {
    const userId = req.user.userId;

    db.query(
        'SELECT id, username, email FROM users WHERE id != ?',
        [userId],
        (err, results) => {
            if (err) return res.status(500).json({ error: 'Erreur base de données' });
            res.json(results);
        }
    );
});

// --- Conversations ---
app.post('/conversations', authenticateToken, (req, res) => {
    const userId = req.user.userId;
    const { otherUserId } = req.body;

    const checkQuery = `
        SELECT c.id 
        FROM conversations c
        INNER JOIN conversation_participants cp1 ON c.id = cp1.conversation_id
        INNER JOIN conversation_participants cp2 ON c.id = cp2.conversation_id
        WHERE cp1.user_id = ? AND cp2.user_id = ?
    `;

    db.query(checkQuery, [userId, otherUserId], (err, results) => {
        if (err) return res.status(500).json({ error: 'Erreur vérification conversation' });

        if (results.length > 0) return res.json({ conversationId: results[0].id, exists: true });

        db.query('INSERT INTO conversations () VALUES ()', (err, result) => {
            if (err) return res.status(500).json({ error: 'Erreur création conversation' });

            const conversationId = result.insertId;

            db.query(
                'INSERT INTO conversation_participants (conversation_id, user_id) VALUES (?, ?), (?, ?)',
                [conversationId, userId, conversationId, otherUserId],
                (err) => {
                    if (err) return res.status(500).json({ error: 'Erreur ajout participants' });
                    res.json({ conversationId, exists: false });
                }
            );
        });
    });
});

app.get('/conversations', authenticateToken, (req, res) => {
    const userId = req.user.userId;

    const query = `
        SELECT 
            c.id,
            c.updated_at,
            u.username as other_user,
            u.id as other_user_id,
            m.content as last_message,
            m.created_at as last_message_time
        FROM conversations c
        INNER JOIN conversation_participants cp1 ON c.id = cp1.conversation_id
        INNER JOIN conversation_participants cp2 ON c.id = cp2.conversation_id
        INNER JOIN users u ON cp2.user_id = u.id
        LEFT JOIN messages m ON c.id = m.conversation_id
        WHERE cp1.user_id = ? 
            AND cp2.user_id != ?
            AND (m.id IS NULL OR m.id = (
                SELECT id FROM messages 
                WHERE conversation_id = c.id 
                ORDER BY created_at DESC 
                LIMIT 1
            ))
        ORDER BY c.updated_at DESC
    `;

    db.query(query, [userId, userId], (err, results) => {
        if (err) return res.status(500).json({ error: 'Erreur base de données' });
        res.json(results);
    });
});

app.get('/messages/:conversationId', authenticateToken, (req, res) => {
    const { conversationId } = req.params;

    db.query(
        `SELECT m.*, u.username as sender_name 
         FROM messages m 
         INNER JOIN users u ON m.sender_id = u.id 
         WHERE m.conversation_id = ? 
         ORDER BY m.created_at ASC`,
        [conversationId],
        (err, results) => {
            if (err) return res.status(500).json({ error: 'Erreur base de données' });
            res.json(results);
        }
    );
});

// --- Socket.io ---
io.on('connection', (socket) => {
    console.log('Utilisateur connecté:', socket.id);

    socket.on('join_conversation', (conversationId) => {
        socket.join(conversationId);
        console.log(`Utilisateur rejoint la conversation: ${conversationId}`);
    });

    socket.on('send_message', (data) => {
        const { conversationId, senderId, content } = data;

        db.query(
            'INSERT INTO messages (conversation_id, sender_id, content) VALUES (?, ?, ?)',
            [conversationId, senderId, content],
            (err, result) => {
                if (err) return console.error('Erreur sauvegarde message:', err);

                db.query(
                    `SELECT m.*, u.username as sender_name 
                     FROM messages m 
                     INNER JOIN users u ON m.sender_id = u.id 
                     WHERE m.id = ?`,
                    [result.insertId],
                    (err, messageResults) => {
                        if (err || messageResults.length === 0) return;

                        const message = messageResults[0];

                        db.query('UPDATE conversations SET updated_at = NOW() WHERE id = ?', [conversationId]);

                        io.to(conversationId).emit('new_message', message);
                    }
                );
            }
        );
    });

    socket.on('disconnect', () => {
        console.log('Utilisateur déconnecté:', socket.id);
    });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
    console.log(`Serveur démarré sur le port ${PORT}`);
});
