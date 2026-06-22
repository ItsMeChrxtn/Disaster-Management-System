const Config = window.DISASTER_MAP_CONFIG;
const Api = {
  token: () => sessionStorage.getItem('dm_token'),
  async request(path, options = {}) {
    const requestId=crypto.randomUUID?.()||`${Date.now()}-${Math.random()}`;
    document.dispatchEvent(new CustomEvent('api:start',{detail:{requestId,path,method:options.method||'GET'}}));
    const headers = {'Content-Type':'application/json', ...(options.headers || {})};
    if (this.token()) headers.Authorization = `Bearer ${this.token()}`;
    try{
      const response = await fetch(`${Config.API_URL}${path}`, {...options, headers});
      const payload = await response.json().catch(() => ({success:false,message:'Invalid server response'}));
      if (!response.ok) { if(response.status===401){sessionStorage.removeItem('dm_token');sessionStorage.removeItem('dm_user');if(!location.pathname.endsWith('/login.html'))setTimeout(()=>location.href='login.html',900);} const error=new Error(payload.message || 'Request failed');error.status=response.status;error.errors=payload.errors||{};document.dispatchEvent(new CustomEvent('api:error',{detail:error}));throw error; }
      return payload.data;
    } catch(error) {
      if(!error.status){const networkError=new Error('The server could not be reached. Check your connection and try again.');networkError.status=0;document.dispatchEvent(new CustomEvent('api:error',{detail:networkError}));throw networkError;}throw error;
    } finally { document.dispatchEvent(new CustomEvent('api:end',{detail:{requestId,path,method:options.method||'GET'}})); }
  },
  get: path => Api.request(path),
  post: (path, data) => Api.request(path,{method:'POST',body:JSON.stringify(data)}),
  put: (path, data) => Api.request(path,{method:'PUT',body:JSON.stringify(data)}),
  delete: path => Api.request(path,{method:'DELETE'})
};
