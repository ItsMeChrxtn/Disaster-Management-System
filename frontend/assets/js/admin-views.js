window.AdminViews=(()=>{
  function entries(){
    return [...document.querySelectorAll('#sidebar [data-view][data-view-src]')].map(button=>({
      id:button.dataset.view,
      src:button.dataset.viewSrc
    }));
  }

  function load(){
    const container=document.querySelector('[data-admin-view-container]');
    if(!container)return;
    const modules=entries();
    const markup=modules.map(module=>{
      const request=new XMLHttpRequest();
      request.open('GET',`${module.src}?v=20260712-users-no-emailjs`,false);
      request.send(null);
      if(request.status!==0&&(request.status<200||request.status>=300)){
        throw new Error(`Unable to load ${module.id} from ${module.src}`);
      }
      const html=request.responseText;
      if(!html.includes(`id="view-${module.id}"`)){
        throw new Error(`View file mismatch: ${module.src} must contain #view-${module.id}`);
      }
      return html;
    }).join('');
    container.innerHTML=markup;
    container.dataset.adminViewsReady='true';
    document.dispatchEvent(new CustomEvent('admin:views-ready',{detail:{views:modules}}));
  }

  try{load();}catch(error){
    const container=document.querySelector('[data-admin-view-container]');
    if(container)container.innerHTML=`<div class="rounded-2xl border border-red-200 bg-red-50 p-6 text-sm text-red-700">${error.message}</div>`;
    throw error;
  }

  return {entries,load,ready:Promise.resolve()};
})();
