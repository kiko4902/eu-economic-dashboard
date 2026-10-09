-- Full replace: the extract deletes and reloads a dataset inside one transaction.
DELETE FROM raw.{table};
