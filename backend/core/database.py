import sqlite3
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional, Any
import json
from core.logger import setup_logger

logger = setup_logger(__name__)


class ConversationDB:
    """SQLite database for conversation persistence."""
    
    def __init__(self, db_path: str = "./data/conversations.db"):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()
    
    def _init_db(self):
        """Initialize database schema."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                system_prompt TEXT,
                model TEXT DEFAULT 'gpt-4o',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                conversation_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                reasoning TEXT,
                metadata TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
            )
        """)
        
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_conversation_messages 
            ON messages(conversation_id, created_at)
        """)
        
        conn.commit()
        conn.close()
        logger.info("Conversation database initialized")
    
    def create_conversation(self, conv_id: str, title: str = "New Chat", 
                          system_prompt: Optional[str] = None,
                          model: str = "gpt-4o") -> Dict[str, Any]:
        """Create a new conversation."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        try:
            cursor.execute(
                """INSERT INTO conversations (id, title, system_prompt, model) 
                   VALUES (?, ?, ?, ?)""",
                (conv_id, title, system_prompt, model)
            )
            conn.commit()
            
            return {
                "id": conv_id,
                "title": title,
                "system_prompt": system_prompt,
                "model": model,
                "created_at": datetime.now().isoformat()
            }
        except sqlite3.IntegrityError:
            logger.warning(f"Conversation {conv_id} already exists")
            return self.get_conversation(conv_id)
        finally:
            conn.close()
    
    def get_conversation(self, conv_id: str) -> Optional[Dict[str, Any]]:
        """Get conversation metadata."""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        cursor.execute("SELECT * FROM conversations WHERE id = ?", (conv_id,))
        row = cursor.fetchone()
        conn.close()
        
        if row:
            return dict(row)
        return None
    
    def list_conversations(self, limit: int = 50) -> List[Dict[str, Any]]:
        """List all conversations ordered by last update."""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        cursor.execute(
            """SELECT * FROM conversations 
               ORDER BY updated_at DESC LIMIT ?""",
            (limit,)
        )
        rows = cursor.fetchall()
        conn.close()
        
        return [dict(row) for row in rows]
    
    def update_conversation(self, conv_id: str, **kwargs):
        """Update conversation metadata."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        allowed_fields = ['title', 'system_prompt', 'model']
        updates = []
        values = []
        
        for field, value in kwargs.items():
            if field in allowed_fields:
                updates.append(f"{field} = ?")
                values.append(value)
        
        if updates:
            updates.append("updated_at = CURRENT_TIMESTAMP")
            values.append(conv_id)
            
            query = f"UPDATE conversations SET {', '.join(updates)} WHERE id = ?"
            cursor.execute(query, values)
            conn.commit()
        
        conn.close()
    
    def delete_conversation(self, conv_id: str):
        """Delete a conversation and all its messages."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute("DELETE FROM conversations WHERE id = ?", (conv_id,))
        conn.commit()
        conn.close()
        logger.info(f"Deleted conversation {conv_id}")
    
    def add_message(self, conv_id: str, role: str, content: str,
                   reasoning: Optional[str] = None,
                   metadata: Optional[Dict] = None) -> int:
        """Add a message to a conversation."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        metadata_json = json.dumps(metadata) if metadata else None
        
        cursor.execute(
            """INSERT INTO messages (conversation_id, role, content, reasoning, metadata)
               VALUES (?, ?, ?, ?, ?)""",
            (conv_id, role, content, reasoning, metadata_json)
        )
        
        cursor.execute(
            "UPDATE conversations SET updated_at = CURRENT_TIMESTAMP WHERE id = ?",
            (conv_id,)
        )
        
        message_id = cursor.lastrowid
        conn.commit()
        conn.close()
        
        return message_id
    
    def get_messages(self, conv_id: str, limit: int = 100) -> List[Dict[str, Any]]:
        """Get all messages in a conversation."""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        cursor.execute(
            """SELECT * FROM messages 
               WHERE conversation_id = ? 
               ORDER BY created_at ASC LIMIT ?""",
            (conv_id, limit)
        )
        rows = cursor.fetchall()
        conn.close()
        
        messages = []
        for row in rows:
            msg = dict(row)
            if msg['metadata']:
                msg['metadata'] = json.loads(msg['metadata'])
            messages.append(msg)
        
        return messages
    
    def export_conversation(self, conv_id: str) -> Dict[str, Any]:
        """Export a complete conversation."""
        conversation = self.get_conversation(conv_id)
        if not conversation:
            return None
        
        messages = self.get_messages(conv_id)
        
        return {
            "conversation": conversation,
            "messages": messages,
            "exported_at": datetime.now().isoformat()
        }


conversation_db = ConversationDB()
