// Memory only: no customer records or signed URLs are stored on disk.
export class RequestCache<T>{
 private values=new Map<string,{value:T;until:number}>();
 private pending=new Map<string,Promise<T>>();
 private generation=0;
 constructor(private ttl:number){}
 clear(){this.generation++;this.values.clear();this.pending.clear()}
 async get(key:string,fetcher:()=>Promise<T>):Promise<T>{
  const cached=this.values.get(key);if(cached&&cached.until>Date.now())return cached.value;
  const active=this.pending.get(key);if(active)return active;
  const generation=this.generation;
  const request=fetcher().then(value=>{if(generation===this.generation)this.values.set(key,{value,until:Date.now()+this.ttl});return value}).finally(()=>{if(this.pending.get(key)===request)this.pending.delete(key)});
  this.pending.set(key,request);return request;
 }
}
