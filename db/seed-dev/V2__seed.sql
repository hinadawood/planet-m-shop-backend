INSERT INTO categories (name, slug, description) VALUES
 ('Bedroom', 'bedroom', 'Bed sheets, pillow covers and duvet covers'),
 ('Dining', 'dining', 'Table runners, placemats and napkins'),
 ('Living', 'living', 'Cushion covers, sofa sets and throws'),
 ('Outdoor', 'outdoor', 'Weather-resistant outdoor linens');

INSERT INTO products (sku, name, description, category_id, price, material, size, color) VALUES
 ('BED-SHT-QN-WHT', 'Cotton Bed Sheet Set (Queen)', 'Breathable 300 thread-count cotton', (SELECT id FROM categories WHERE slug='bedroom'), 89.00, 'Cotton', 'Queen', 'White'),
 ('DIN-RUN-180-NVY', 'Linen Dining Runner', 'Hand-finished linen table runner', (SELECT id FROM categories WHERE slug='dining'), 34.50, 'Linen', '180cm', 'Navy'),
 ('LIV-CSH-45-OCH', 'Cushion Cover 45x45', 'Textured weave cushion cover', (SELECT id FROM categories WHERE slug='living'), 19.99, 'Cotton blend', '45x45cm', 'Ochre'),
 ('LIV-SOF-3S-GRY', 'Sofa Cover Set (3-seater)', 'Stretch fit sofa cover set', (SELECT id FROM categories WHERE slug='living'), 129.00, 'Polyester', '3-seater', 'Grey'),
 ('OUT-CSH-50-TEAL', 'Outdoor Cushion Cover', 'Water-resistant outdoor cover', (SELECT id FROM categories WHERE slug='outdoor'), 24.00, 'Acrylic', '50x50cm', 'Teal');

INSERT INTO inventory (product_id, quantity_on_hand, reorder_level)
SELECT id, 25, 5 FROM products;
