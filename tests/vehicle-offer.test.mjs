import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import ts from 'typescript';
const require=createRequire(import.meta.url);
function load(path,motor){const source=ts.transpileModule(readFileSync(new URL(path,import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText;const exports={};new Function('require','exports',source)(name=>name.endsWith('/motor')?motor:require(name),exports);return exports}
const motor=load('../src/lib/motor.ts');const {VehicleOffer}=load('../src/components/vehicle-offer.tsx',motor);const {printRecord}=load('../src/lib/print.ts',motor);
const {createElement}=require('react');const {renderToStaticMarkup}=require('react-dom/server');
const stock={...motor.blankBike,id:32,stockNo:1,brand:'YAMAHA',model:'Y15',price:100000,originalPrice:130000,installmentFrom:9900,installmentTerms:'36 bulan <terma>',bikeCondition:'new',paid:70000};
test('customer offer distinguishes original price, selling price and monthly starting price',()=>{const html=renderToStaticMarkup(createElement(VehicleOffer,{vehicle:stock,detail:true}));assert.ok(html.includes('<del>'));assert.ok(html.includes(motor.money(130000)));assert.ok(html.includes(motor.money(100000)));assert.ok(html.includes(motor.money(9900)));assert.ok(html.includes('Harga selepas diskaun'));assert.ok(html.includes('36 bulan &lt;terma&gt;'))});
test('ordinary cash listings do not advertise an invented discount or loan offer',()=>{const html=renderToStaticMarkup(createElement(VehicleOffer,{vehicle:{...stock,originalPrice:null,installmentFrom:null}}));assert.ok(!html.includes('<del>'));assert.ok(!html.includes('Ansuran'));assert.ok(html.includes('Harga jualan'))});
test('invoice totals and customer balance use final selling price, not list price or installment',()=>{let html='';globalThis.location={origin:'https://motor.example',pathname:'/'};globalThis.window={open:()=>({addEventListener(){},document:{write(v){html=v},close(){}}})};printRecord(stock,[],'invoice');assert.ok(html.includes('3AM-0001'));assert.ok(html.includes('Jumlah: <b>'+motor.money(100000)+'</b>'));assert.ok(html.includes('Baki: <b>'+motor.money(30000)+'</b>'));assert.ok(html.includes('Harga asal '+motor.money(130000)));assert.ok(!html.includes(motor.money(9900)))});
