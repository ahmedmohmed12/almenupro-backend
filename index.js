const express = require('express');
const mysql = require('mysql2');
const cors = require('cors');

const app = express();
const PORT = 3000;

// Middleware
app.use(express.json());
app.use(cors());

// الاتصال بقاعدة بيانات MySQL المربوطة بـ XAMPP
const db = mysql.createConnection({
    host: 'localhost',
    user: 'root',      // المستخدم الافتراضي في XAMPP
    password: '',      // كلمة السر فارغة افتراضياً في XAMPP
    database: 'molten_db'
});

db.connect((err) => {
    if (err) {
        console.error('❌ خطأ في الاتصال بقاعدة البيانات:', err.message);
    } else {
        console.log('✅ تم الاتصال بقاعدة بيانات MySQL (molten_db) بنجاح!');
    }
});

// 1. API لجلب كافة الأصناف من المنيو
app.get('/api/items', (req, res) => {
    const query = `
        SELECT 
            items.id, 
            items.category_id, 
            categories.name AS category_name, 
            items.name, 
            items.description, 
            items.price, 
            items.image_url, 
            items.is_available 
        FROM items 
        LEFT JOIN categories ON items.category_id = categories.id
    `;

    db.query(query, (err, results) => {
        if (err) {
            return res.status(500).json({ error: err.message });
        }
        res.json(results);
    });
});

// 2. API لإضافة صنف جديد
app.post('/api/items', (req, res) => {
    const { category_id, name, description, price, image_url } = req.body;

    const query = `
        INSERT INTO items (category_id, name, description, price, image_url) 
        VALUES (?, ?, ?, ?, ?)
    `;

    db.query(query, [category_id, name, description, price, image_url], (err, result) => {
        if (err) {
            return res.status(500).json({ error: err.message });
        }
        res.status(201).json({ message: 'تم إضافة الصنف بنجاح', id: result.insertId });
    });
});

// تشغيل السيرفر
app.listen(PORT, () => {
    console.log(`🚀 السيرفر يعمل الآن على الرابط: http://localhost:${PORT}`);
});
