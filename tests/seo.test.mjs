import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
function load(path,deps={}){const source=ts.transpileModule(readFileSync(new URL(path,import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS}}).outputText;const exports={};new Function('require','exports',source)(n=>deps[n],exports);return exports}
const business=load('../src/lib/business.ts');const seo=load('../src/lib/seo.ts',{'./business':business});
const bike={id:7,brand:'YAMAHA',model:'Y15ZR',year:2024,mileage:12000,price:780000,cost:500000,prep:20000,paid:100000,buyer:'Private Buyer',buyerPhone:'60123456789',supplier:'Secret supplier',chassis:'MH3SECRET',status:'available',bikeCondition:'pre_owned'};
test('catalogue structured data exposes only public listing fields',()=>{const s=seo.catalogueSchema([bike]);const text=JSON.stringify(s);
 for(const secret of ['500000','Private Buyer','60123456789','Secret supplier','MH3SECRET','5000.00'])assert.ok(!text.includes(secret),secret);
 const item=s.itemListElement[0].item;assert.equal(item.offers.price,'7800.00');assert.equal(item.offers.priceCurrency,'MYR');assert.equal(item.itemCondition,'https://schema.org/UsedCondition');assert.equal(item.mileageFromOdometer.value,12000);assert.equal(s.itemListElement[0].url,'https://3abdulmotor.binalab.my/#catalogue?motor=7')});
test('business structured data only includes valid contact links',()=>{const s=seo.businessSchema({id:1,whatsappPhone:'60123456789',whatsappTemplate:'',version:1,facebookUrl:'https://facebook.com/x',tiktokUrl:'javascript:alert(1)',mapsUrl:''});assert.equal(s.telephone,'+60123456789');assert.deepEqual(s.sameAs,['https://facebook.com/x']);assert.equal('hasMap' in s,false);
 assert.equal('telephone' in seo.businessSchema({id:1,whatsappPhone:'',whatsappTemplate:'',version:1}),false)});
