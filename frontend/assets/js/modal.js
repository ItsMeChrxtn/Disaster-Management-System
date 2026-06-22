const Modal = (()=>{
  const registry=new Map();
  const labels={
    hazardFormCard:['Hazard details','Define the hazard area and operational risk level.'],safeZoneFormCard:['Safe zone details','Maintain a verified public safety location.'],centerFormCard:['Evacuation center details','Update facility capacity and operating status.'],alertFormCard:['Alert details','Create and target an emergency notification.'],historicalFormCard:['Historical record','Document verified disaster impact information.'],userPanel:['User account','Manage access, role, and assigned municipality.'],municipalityPanel:['Municipality details','Maintain the jurisdiction directory.'],reportForm:['Generate operational report','Choose report scope, dates, and export format.'],saveRouteForm:['Save evacuation route','Store the currently visualized route for future use.']
  };
  function enhance(id){
    const root=document.getElementById(id);if(!root)return;
    const wasHidden=root.classList.contains('hidden'),isForm=root.tagName==='FORM';
    root.className=`crud-modal fixed inset-0 z-[1000] ${wasHidden?'hidden':'flex'} items-end justify-center bg-slate-950/70 p-0 backdrop-blur-sm sm:items-center sm:p-5`;
    root.setAttribute('role','dialog');root.setAttribute('aria-modal','true');root.setAttribute('aria-labelledby',`${id}ModalTitle`);
    const children=[...root.childNodes],dialog=document.createElement('div');dialog.className='modal-dialog animate__animated animate__fadeInUp animate__faster w-full overflow-hidden rounded-t-3xl border border-white/10 bg-white shadow-2xl dark:bg-slate-900 sm:max-h-[92vh] sm:max-w-2xl sm:rounded-3xl';
    if(id==='reportForm'){root.classList.add('report-modal');dialog.classList.add('report-modal-dialog');}
    const [title,subtitle]=labels[id]||['Form details','Complete the fields below.'];
    dialog.innerHTML=`<header class="modal-header"><div><p class="modal-eyebrow">Disaster Map Operations</p><h2 id="${id}ModalTitle">${title}</h2><p>${subtitle}</p></div><button type="button" data-modal-close aria-label="Close modal">×</button></header>`;
    const body=document.createElement('div');body.className='modal-body';children.forEach(node=>body.appendChild(node));dialog.appendChild(body);
    if(!isForm){const legacyHeader=body.querySelector(':scope > .flex.items-center.justify-between');if(legacyHeader)legacyHeader.classList.add('hidden');}
    const form=isForm?root:body.querySelector('form');
    if(form){
      form.classList.remove('rounded-2xl','border','bg-white','p-5','p-6','space-y-3','space-y-4');(isForm?body:form).classList.add('modal-form');
      const currentSubmit=form.querySelector('button[type="submit"],button:not([type])');
      if(currentSubmit){currentSubmit.type='submit';currentSubmit.className='button button-primary';const actions=document.createElement('footer');actions.className='modal-actions';actions.innerHTML='<button type="button" data-modal-close class="button button-secondary">Cancel</button>';actions.appendChild(currentSubmit);(isForm?body:form).appendChild(actions);}
      form.addEventListener('submit',event=>{if(!form.checkValidity()){event.preventDefault();event.stopImmediatePropagation();Alerts.validation(form);return;}if(currentSubmit){currentSubmit.dataset.label=currentSubmit.textContent;currentSubmit.disabled=true;currentSubmit.innerHTML='<span class="button-spinner"></span> Saving…';setTimeout(()=>{if(currentSubmit.disabled){currentSubmit.disabled=false;currentSubmit.textContent=currentSubmit.dataset.label||'Save';}},15000);}} ,true);
      document.addEventListener('api:end',()=>{if(currentSubmit?.disabled){currentSubmit.disabled=false;currentSubmit.textContent=currentSubmit.dataset.label||'Save';}});
    }
    root.appendChild(dialog);
    // Fixed dialogs must live directly under body. Animated view containers can
    // create containing blocks that clip or position fixed children incorrectly.
    document.body.appendChild(root);
    root.addEventListener('click',event=>{if(event.target===root||event.target.closest('[data-modal-close]'))close(root);});
    new MutationObserver(()=>{if(!root.classList.contains('hidden')){document.body.classList.add('modal-open');setTimeout(()=>dialog.querySelector('input:not([type="hidden"]),select,textarea')?.focus(),80);}else document.body.classList.remove('modal-open');}).observe(root,{attributes:true,attributeFilter:['class']});
    registry.set(id,root);
  }
  function open(target){const root=typeof target==='string'?registry.get(target)||document.getElementById(target):target;if(!root)return;root.classList.remove('hidden');root.classList.add('flex');}
  function close(target){const root=typeof target==='string'?registry.get(target)||document.getElementById(target):target;if(!root)return;root.classList.add('hidden');root.classList.remove('flex');}
  function init(){Object.keys(labels).forEach(enhance);document.addEventListener('keydown',event=>{if(event.key==='Escape'){const active=[...document.querySelectorAll('.crud-modal:not(.hidden)')].pop();if(active)close(active);}});
    const report=document.getElementById('reportForm');if(report){const account=JSON.parse(sessionStorage.getItem('dm_user')||'null');if(!['admin','subadmin'].includes(account?.role)){report.remove();return;}if(account.role==='admin'&&!report.elements.municipality_id){const label=document.createElement('label');label.className='block text-sm font-medium report-scope';label.innerHTML='Municipality scope<select name="municipality_id" class="mt-1 w-full rounded-lg border p-3"><option value="">Province-wide</option></select>';report.querySelector('label')?.before(label);Api.get('/municipalities/options').then(rows=>rows.forEach(item=>label.querySelector('select').add(new Option(item.municipality_name,item.id)))).catch(()=>{});}const section=document.getElementById('view-reports'),heading=section?.querySelector('h1')?.parentElement,workspace=section?.querySelector('.mt-5.grid');if(workspace){workspace.className='report-workspace mt-6 space-y-5';const table=workspace.querySelector('.overflow-x-auto');table?.classList.remove('xl:col-span-2');table?.classList.add('report-table-card');workspace.insertAdjacentHTML('afterbegin','<div class="report-overview-grid"><article><span>01</span><div><strong>Choose a report</strong><p>Hazards, alerts, historical incidents, or evacuation facilities.</p></div></article><article><span>02</span><div><strong>Set the scope</strong><p>Filter by municipality and reporting period.</p></div></article><article><span>03</span><div><strong>Export securely</strong><p>Generate a traceable PDF or Excel file.</p></div></article></div>');}if(heading){const header=document.createElement('div'),button=document.createElement('button');header.className='page-heading report-page-heading';heading.before(header);header.appendChild(heading);button.id='openReportModalBtn';button.type='button';button.className='button button-primary';button.innerHTML='<span aria-hidden="true">＋</span> Generate report';button.onclick=()=>open('reportForm');header.appendChild(button);}close(report);}
  }
  return {init,open,close};
})();
document.readyState==='loading'?document.addEventListener('DOMContentLoaded',Modal.init):Modal.init();
