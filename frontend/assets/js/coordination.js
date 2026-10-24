// PDRRMO <-> MDRRMO/CDRRMO coordination channel (admin: every municipality; sub-admin: own municipality).
(()=>{
  const user=JSON.parse(sessionStorage.getItem('dm_user')||'null');
  const view=document.getElementById('view-coordination');
  if(!user||!['admin','subadmin'].includes(user.role)){view?.remove();return;}
  const isAdmin=user.role==='admin';
  const officeOf=name=>/city/i.test(name||'')?'CDRRMO':'MDRRMO';
  const categoryLabels={advisory:'Advisory',directive:'Directive',situation_report:'Situation report',request:'Request',response:'Response',general:'Message'};
  const esc=value=>{const el=document.createElement('span');el.textContent=value??'';return el.innerHTML;};
  const when=value=>{if(!value)return '';const date=new Date(String(value).replace(' ','T')+(/[zZ]|[+-]\d\d:?\d\d$/.test(value)?'':'+08:00'));return Number.isNaN(date.getTime())?value:date.toLocaleString('en-PH',{month:'short',day:'numeric',hour:'numeric',minute:'2-digit'});};
  let channels=[],current=null,pollTimer=null,loading=false;

  function setBadge(){
    const badge=document.getElementById('coordinationBadge');if(!badge)return;
    const count=channels.reduce((total,c)=>total+c.unread+(isAdmin?0:c.pending_ack),0);
    badge.textContent=count;badge.classList.toggle('hidden',!count);
  }
  async function loadChannels(){
    try{const data=await Api.get('/coordination/channels');channels=data.channels||[];setBadge();renderRegistryStrip();if(isVisible())renderChannels();return data;}
    catch(error){if(isVisible())document.getElementById('coordinationChannelList').innerHTML=`<p class="muted-note">${esc(error.message)}</p>`;}
  }
  // Summary on the admin Municipalities registry: unread LGU reports and unacknowledged directives.
  function renderRegistryStrip(){
    const strip=document.getElementById('municipalCoordinationStrip');if(!strip||!isAdmin)return;
    const unread=channels.reduce((t,c)=>t+c.unread,0),pending=channels.filter(c=>c.pending_ack>0).length,noOfficer=channels.filter(c=>!c.officers).length;
    strip.innerHTML=`<div><span>MDRRMO / CDRRMO coordination</span><strong>${unread?`${unread} new report${unread===1?'':'s'} from LGUs`:'No unread LGU reports'}</strong><small>${pending?`${pending} LGU${pending===1?'':'s'} still to acknowledge a directive`:'All directives acknowledged'}${noOfficer?` · ${noOfficer} without an officer account`:''}</small></div><a href="coordination.html" data-open-view="coordination" class="button button-primary button-sm">Alert / message LGUs</a>`;
  }
  function isVisible(){return view&&!view.classList.contains('hidden');}

  function renderChannels(){
    const list=document.getElementById('coordinationChannelList'),query=(document.getElementById('coordinationChannelSearch')?.value||'').toLowerCase().trim();
    document.getElementById('coordinationOffice').textContent=isAdmin?'PDRRMO channels':`${officeOf(user.municipality_name)} ${user.municipality_name||''}`;
    const items=channels.filter(c=>!query||c.municipality_name.toLowerCase().includes(query)).map(c=>{
      const last=c.last_message;
      const flags=[c.unread?`<b class="channel-unread">${c.unread} new</b>`:'',c.pending_ack?`<b class="channel-pending" title="Directives not yet acknowledged">${c.pending_ack} awaiting ack</b>`:''].join('');
      return `<button type="button" class="coordination-channel${String(current)===String(c.municipality_id)?' is-active':''}" data-channel="${c.municipality_id}"><span class="channel-avatar">${esc(c.office)}</span><span class="channel-text"><strong>${esc(c.municipality_name)}</strong><small>${last?esc((last.direction==='to_province'?`${c.office}: `:'PDRRMO: ')+last.subject):(c.officers?`${c.officers} ${c.office} account${c.officers===1?'':'s'}`:'No officer account yet')}</small></span><span class="channel-flags">${flags}${last?`<time>${esc(when(last.created_at))}</time>`:''}</span></button>`;
    });
    const broadcast=isAdmin?`<button type="button" class="coordination-channel is-broadcast${current==='all'?' is-active':''}" data-channel="all"><span class="channel-avatar">ALL</span><span class="channel-text"><strong>All MDRRMO / CDRRMO</strong><small>Province-wide directives and advisories</small></span></button>`:'';
    list.innerHTML=broadcast+(items.join('')||'<p class="muted-note">No matching municipality.</p>');
  }

  function messageMarkup(m){
    const mine=isAdmin?m.direction==='to_lgu':m.direction==='to_province';
    let ack='';
    if(m.direction==='to_lgu'&&m.requires_ack){
      if(current==='all')ack=`<p class="message-ack">Acknowledged by ${m.ack_count||0} of ${channels.length} LGUs</p>`;
      else if(m.acknowledged_at)ack=`<p class="message-ack is-done">Acknowledged by ${esc(m.acknowledged_by||'LGU')} · ${esc(when(m.acknowledged_at))}</p>`;
      else ack=isAdmin?'<p class="message-ack is-waiting">Awaiting acknowledgement</p>':`<button type="button" class="button button-primary button-sm" data-ack="${m.id}">Acknowledge</button>`;
    }
    return `<article class="coordination-message ${mine?'is-mine':'is-theirs'} priority-${esc(m.priority)}"><div class="message-head"><span class="message-sender">${esc(m.sender_office)} · ${esc(m.sender_name)}</span><span class="message-tags"><span class="message-category">${esc(categoryLabels[m.category]||m.category)}</span>${m.priority!=='normal'?`<span class="message-priority">${esc(m.priority)}</span>`:''}${m.is_broadcast&&current!=='all'?'<span class="message-broadcast">All LGUs</span>':''}</span></div><h3>${esc(m.subject)}</h3><p>${esc(m.body).replace(/\n/g,'<br>')}</p><div class="message-foot"><time>${esc(when(m.created_at))}</time>${ack}</div></article>`;
  }

  async function openChannel(id,{silent=false}={}){
    current=id;loading=true;renderChannels();
    const channel=channels.find(c=>String(c.municipality_id)===String(id));
    document.getElementById('coordinationThreadKicker').textContent=id==='all'?'Broadcast':`${channel?.office||'LGU'} channel`;
    document.getElementById('coordinationThreadTitle').textContent=id==='all'?'All MDRRMO / CDRRMO':(channel?.municipality_name||user.municipality_name||'Municipality');
    document.getElementById('coordinationThreadMeta').textContent=id==='all'?`Messages here reach all ${channels.length} municipal and city DRRM offices.`:(isAdmin?`${channel?.officers||0} active ${channel?.office||'LGU'} account(s) · PDRRMO ↔ ${channel?.office||'LGU'}`:'Your direct line to the PDRRMO. Province-wide broadcasts also appear here.');
    document.getElementById('coordinationTargets').classList.toggle('hidden',!(isAdmin&&id==='all'));
    const box=document.getElementById('coordinationMessages');if(!silent)box.innerHTML='<p class="muted-note">Loading messages&hellip;</p>';
    try{
      const data=await Api.get(`/coordination/messages?municipality_id=${encodeURIComponent(id)}`);
      const nearBottom=box.scrollHeight-box.scrollTop-box.clientHeight<80;
      box.innerHTML=(data.messages||[]).map(messageMarkup).join('')||`<div class="coordination-empty"><strong>No messages yet</strong><p>${isAdmin?'Send an advisory or directive to start the channel.':'Send a situation report or request to the PDRRMO.'}</p></div>`;
      if(!silent||nearBottom)box.scrollTop=box.scrollHeight;
      if(channel&&id!=='all'){channel.unread=0;setBadge();renderChannels();}
    }catch(error){box.innerHTML=`<p class="muted-note">${esc(error.message)}</p>`;}
    finally{loading=false;}
  }

  function renderTargetPicker(){
    const picker=document.getElementById('coordinationTargetPicker');
    if(picker.dataset.ready)return;picker.dataset.ready='1';
    picker.innerHTML=channels.map(c=>`<label><input type="checkbox" value="${c.municipality_id}"> ${esc(c.municipality_name)}</label>`).join('');
  }

  async function show(){
    const data=await loadChannels();if(!data)return;
    renderChannels();
    const requested=new URLSearchParams(location.search).get('municipality');
    const target=current??(isAdmin?(requested&&channels.some(c=>String(c.municipality_id)===requested)?requested:'all'):channels[0]?.municipality_id);
    if(target!=null)openChannel(target);
    if(isAdmin)renderTargetPicker();
    clearInterval(pollTimer);pollTimer=setInterval(async()=>{if(!isVisible()){clearInterval(pollTimer);return;}await loadChannels();if(current!=null&&!loading)openChannel(current,{silent:true});},20000);
  }

  const form=document.getElementById('coordinationForm');
  if(!isAdmin){form.elements.category.value='situation_report';document.getElementById('coordinationTitle').textContent=`${officeOf(user.municipality_name)} ↔ PDRRMO`;document.getElementById('coordinationSubtitle').textContent='Report incidents and needs to the Provincial DRRM Office and acknowledge provincial directives.';}
  else form.elements.category.value='advisory';

  document.getElementById('coordinationChannelList')?.addEventListener('click',e=>{const item=e.target.closest('[data-channel]');if(item)openChannel(item.dataset.channel);});
  document.getElementById('coordinationChannelSearch')?.addEventListener('input',renderChannels);
  document.getElementById('coordinationRefresh')?.addEventListener('click',()=>{loadChannels();if(current!=null)openChannel(current);});
  document.getElementById('coordinationTargets')?.addEventListener('change',e=>{if(e.target.name==='target_mode')document.getElementById('coordinationTargetPicker').classList.toggle('hidden',e.target.value!=='selected');});
  document.getElementById('coordinationMessages')?.addEventListener('click',async e=>{
    const button=e.target.closest('[data-ack]');if(!button)return;button.disabled=true;
    try{await Api.post(`/coordination/messages/${button.dataset.ack}/acknowledge`,{});toast('Acknowledged — the PDRRMO has been notified');await loadChannels();openChannel(current,{silent:true});}
    catch(error){button.disabled=false;showError(error.message);}
  });
  form?.addEventListener('submit',async e=>{
    e.preventDefault();
    const error=document.getElementById('coordinationError'),button=form.querySelector('button[type="submit"]'),data=Object.fromEntries(new FormData(form));
    error.classList.add('hidden');
    const payload={category:data.category,priority:data.priority,subject:data.subject,body:data.body,requires_ack:!!data.requires_ack};
    if(isAdmin){
      if(current==='all'){
        if(data.target_mode==='selected'){payload.municipality_ids=[...document.querySelectorAll('#coordinationTargetPicker input:checked')].map(input=>Number(input.value));if(!payload.municipality_ids.length){error.textContent='Select at least one municipality.';error.classList.remove('hidden');return;}}
        else payload.municipality_ids='all';
      }else payload.municipality_ids=[Number(current)];
    }
    button.disabled=true;button.textContent='Sending…';
    try{const result=await Api.post('/coordination/messages',payload);form.elements.subject.value='';form.elements.body.value='';if(form.elements.requires_ack)form.elements.requires_ack.checked=false;toast(result.message||'Message sent');await loadChannels();openChannel(current,{silent:true});}
    catch(err){error.textContent=err.message;error.classList.remove('hidden');}
    finally{button.disabled=false;button.textContent='Send';}
  });

  document.addEventListener('admin:view',e=>{if(e.detail.view==='coordination')show();});
  if(isVisible())show();
  loadChannels();setInterval(()=>{if(!isVisible())loadChannels();},60000);
})();
