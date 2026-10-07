export const PHOTO_MAX_BYTES=256*1024;
export async function preparePhoto(file:File):Promise<Blob>{
 if(!['image/jpeg','image/png','image/webp'].includes(file.type)||file.size>20*1024*1024)throw Error('Gunakan JPG, PNG atau WebP di bawah 20 MB.');
 let bitmap:ImageBitmap;
 try{bitmap=await createImageBitmap(file)}catch{throw Error('Gambar tidak dapat dibaca. Cuba gambar JPG lain.');}
 try{
  if(!bitmap.width||!bitmap.height||bitmap.width*bitmap.height>50_000_000)throw Error('Resolusi gambar terlalu besar. Pilih gambar yang lebih kecil.');
  const canvas=document.createElement('canvas');const context=canvas.getContext('2d');if(!context)throw Error('Pemprosesan gambar tidak tersedia.');
  let edge=1280;
  for(let pass=0;pass<5;pass++){
   const scale=Math.min(1,edge/Math.max(bitmap.width,bitmap.height));canvas.width=Math.max(1,Math.round(bitmap.width*scale));canvas.height=Math.max(1,Math.round(bitmap.height*scale));
   context.fillStyle='#ffffff';context.fillRect(0,0,canvas.width,canvas.height);context.drawImage(bitmap,0,0,canvas.width,canvas.height);
   for(const quality of [.82,.7,.58]){
    let blob=await new Promise<Blob|null>(resolve=>canvas.toBlob(resolve,'image/webp',quality));
    if(blob?.type!=='image/webp')blob=await new Promise<Blob|null>(resolve=>canvas.toBlob(resolve,'image/jpeg',quality));
    if(blob&&blob.size<=PHOTO_MAX_BYTES)return blob;
   }
   edge=Math.round(edge*.75);
  }
  throw Error('Gambar belum dapat dikecilkan. Cuba gambar lain.');
 }finally{bitmap.close()}
}
