-- Removes outbox rows that were published to Cassandra more than 7 days ago. Unpublished rows are never touched.
DELETE FROM outbox_events
 WHERE published_at IS NOT NULL
   AND published_at < now() - interval '7 days';
