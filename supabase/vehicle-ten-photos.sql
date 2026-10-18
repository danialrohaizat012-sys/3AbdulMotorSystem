-- Run in the dedicated 3 Abdul Motor project, before deploying the matching UI.
-- Preserve the CURRENT vehicle guard, including permission and ledger checks.
begin;
do $migration$
declare current_definition text; updated_definition text; matches integer;
begin
 current_definition:=pg_get_functiondef('private.guard_vehicle()'::regprocedure);
 matches:=(length(current_definition)-length(replace(current_definition,'cardinality(NEW.photos)>5','')))/length('cardinality(NEW.photos)>5');
 if matches<>2 then
  raise exception 'Unexpected photo guard version: expected two five-photo checks; review current function before rollout.';
 end if;
 updated_definition:=replace(current_definition,'cardinality(NEW.photos)>5','cardinality(NEW.photos)>10');
 updated_definition:=replace(updated_definition,'Maksimum 5 gambar setiap stok.','Maksimum 10 gambar setiap stok.');
 execute updated_definition;
end;
$migration$;
commit;
