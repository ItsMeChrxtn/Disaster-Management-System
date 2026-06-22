const form=document.getElementById('loginForm'),error=document.getElementById('error');
if(Api.token())location.href='dashboard.html?v=20260620-hazard2';
form.addEventListener('submit',async e=>{e.preventDefault();error.classList.add('hidden');const btn=form.querySelector('button');btn.disabled=true;showLoading('Signing you in…');
  try{const data=Object.fromEntries(new FormData(form)),role=data.role;delete data.role;const result=await Api.post(`/auth/login/${role}`,data);sessionStorage.setItem('dm_token',result.access_token);sessionStorage.setItem('dm_user',JSON.stringify(result.user));sessionStorage.setItem('dm_flash',JSON.stringify({message:`Welcome, ${result.user.fullname}.`,icon:'success'}));closeLoading();location.replace('dashboard.html?v=20260620-hazard2');}
  catch(err){closeLoading();await showError(err.message);}finally{btn.disabled=false;}
});
