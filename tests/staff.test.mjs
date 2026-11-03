import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
const source=ts.transpileModule(readFileSync(new URL('../src/lib/staff.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ES2022}}).outputText;
const {canAccess,can,strongPassword}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
const profile={id:'staff',role:'inventory',enabled:true,must_change_password:false,permissions:{inventory_edit:false,receive_payments:true,manage_whatsapp:false},payment_limit:50000};
test('module access and operation permissions are independent',()=>{assert.equal(canAccess(profile,'inventory'),true);assert.equal(canAccess(profile,'garage'),false);assert.equal(canAccess(profile,'staff'),false);assert.equal(can(profile,'inventory_edit'),false);assert.equal(can(profile,'receive_payments'),true);assert.equal(can(profile,'manage_whatsapp'),false);assert.equal(canAccess({...profile,role:'both'},'garage'),true)});
test('disabled and temporary-password users cannot access operations',()=>{for(const p of [{...profile,enabled:false},{...profile,must_change_password:true}]){assert.equal(canAccess(p,'inventory'),false);assert.equal(can(p,'receive_payments'),false)}assert.equal(canAccess({...profile,role:'owner'},'staff'),true)});
test('temporary passwords must meet stated requirements',()=>{assert.equal(strongPassword('Short_1'),false);assert.equal(strongPassword('lowercaseonly123'),false);assert.equal(strongPassword('Long_Random_2026'),true)});
test('accounting defaults to denied for existing staff profiles',()=>{for(const role of ['inventory','garage','both']){assert.equal(canAccess({...profile,role},'accounting'),false);assert.equal(canAccess({...profile,role},'staff'),false)}assert.equal(canAccess({...profile,role:'owner'},'accounting'),true);assert.equal(canAccess({...profile,role:'both'},'unknown-module'),false)});

test('accounting read, posting and CSV are independent and require read access',()=>{
 for(const role of ['inventory','garage','both']){
  const reader={...profile,role,permissions:{accounting_view:true}};
  assert.equal(canAccess(reader,'accounting'),true);
  assert.equal(can(reader,'accounting_post'),false);assert.equal(can(reader,'accounting_export'),false);
  assert.equal(can({...reader,permissions:{accounting_view:true,accounting_post:true}},'accounting_post'),true);
  assert.equal(can({...reader,permissions:{accounting_view:true,accounting_export:true}},'accounting_export'),true);
  assert.equal(can({...reader,permissions:{accounting_post:true,accounting_export:true}},'accounting_post'),false);
  for(const p of [{...reader,enabled:false},{...reader,must_change_password:true}])assert.equal(canAccess(p,'accounting'),false);
  assert.equal(canAccess(reader,'staff'),false);
 }
});
test('viewing accounting never grants operational edits or owner financial actions',()=>{
 const p={...profile,role:'garage',permissions:{accounting_view:true,accounting_post:true,accounting_export:true}};
 assert.equal(can(p,'inventory_edit'),false);assert.equal(can(p,'garage_edit'),false);
 for(const key of ['accounting_reverse','accounting_manage_accounts','accounting_adjust'])assert.equal(can(p,key),false);
 for(const val of ['true',1,null])assert.equal(canAccess({...p,permissions:{accounting_view:val}},'accounting'),false);
});
