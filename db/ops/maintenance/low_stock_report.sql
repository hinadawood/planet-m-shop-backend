SELECT p.sku, p.name, i.quantity_on_hand - i.quantity_reserved AS available, i.reorder_level
FROM inventory i JOIN products p ON p.id = i.product_id
WHERE i.quantity_on_hand - i.quantity_reserved <= i.reorder_level
ORDER BY available;
