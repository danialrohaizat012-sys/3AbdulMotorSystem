import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
const source=ts.transpileModule(readFileSync(new URL('../src/lib/visitor-day.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ES2022}}).outputText;
const {malaysiaDay}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
test('visitor day rolls over at Malaysia midnight with stable ISO format',()=>{assert.equal(malaysiaDay(new Date('2026-10-06T15:59:59Z')),'2026-10-06');assert.equal(malaysiaDay(new Date('2026-10-06T16:00:00Z')),'2026-10-07');assert.equal(malaysiaDay(new Date('2026-12-31T16:00:00Z')),'2027-01-01')});
