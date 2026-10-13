import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
const source=ts.transpileModule(readFileSync(new URL('../src/lib/business.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ES2022}}).outputText;
const {normalizeFooterUrl,safeFooterUrl}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
test('footer links accept full HTTPS platform/share links and empty values',()=>{for(const u of ['https://www.tiktok.com/@3abdulmotor','https://www.facebook.com/3abdulmotor','https://maps.app.goo.gl/Example','https://wa.me/60123456789?text=Hi%20there'])assert.equal(normalizeFooterUrl(u),u);assert.equal(normalizeFooterUrl('  https://facebook.com  '),'https://facebook.com/');assert.equal(normalizeFooterUrl(''),'')});
test('unsafe schemes, credentials, whitespace and malformed links never reach footer anchors',()=>{for(const u of ['javascript:alert(1)','data:text/html,bad','http://example.com','https://user:password@example.com','https://example.com/a b','https://example.com\\evil','https://','not-a-link']){assert.throws(()=>normalizeFooterUrl(u));assert.equal(safeFooterUrl(u),'')}assert.equal(safeFooterUrl(undefined),'')});
