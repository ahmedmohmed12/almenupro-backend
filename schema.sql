CREATE DATABASE IF NOT EXISTS molten_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE molten_db;

CREATE TABLE IF NOT EXISTS categories (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL
);

CREATE TABLE IF NOT EXISTS items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    category_id INT,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    price DECIMAL(10, 2) NOT NULL,
    image_url VARCHAR(500),
    is_available TINYINT(1) DEFAULT 1,
    FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL
);

INSERT INTO categories (name) VALUES
    ('مشروبات'),
    ('حلويات'),
    ('وجبات رئيسية');

INSERT INTO items (category_id, name, description, price, image_url) VALUES
    (1, 'قهوة عربية', 'قهوة عربية أصيلة', 15.00, NULL),
    (2, 'كنافة', 'كنافة نابلسية', 25.00, NULL),
    (3, 'برجر لحم', 'برجر لحم مشوي', 35.00, NULL);
