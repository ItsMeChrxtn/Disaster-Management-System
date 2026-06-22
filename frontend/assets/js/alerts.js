const Alerts = {
  toast(message, icon='success') {
    return Swal.fire({toast:true,position:'top-end',icon,title:message,showConfirmButton:false,timer:3200,timerProgressBar:true,showClass:{popup:'animate__animated animate__fadeInRight animate__faster'},hideClass:{popup:'animate__animated animate__fadeOutRight animate__faster'}});
  },
  success(title, text='') { return Swal.fire({icon:'success',title,text,confirmButtonText:'Done',confirmButtonColor:'#2563eb'}); },
  error(message, errors={}) {
    const details=Object.values(errors||{}).map(value=>`<li>${this.escape(value)}</li>`).join('');
    return Swal.fire({icon:'error',title:'Unable to complete the request',text:details?'':message,html:details?`<p class="swal-message">${this.escape(message)}</p><ul class="swal-errors">${details}</ul>`:undefined,confirmButtonColor:'#dc2626'});
  },
  async confirm(title,text='This action may affect live operational data.',confirmText='Continue',danger=true) {
    const result=await Swal.fire({title,text,icon:'warning',showCancelButton:true,confirmButtonText:confirmText,cancelButtonText:'Cancel',reverseButtons:true,focusCancel:true,confirmButtonColor:danger?'#dc2626':'#2563eb',cancelButtonColor:'#64748b'});
    return result.isConfirmed;
  },
  loading(title='Processing request…') { Swal.fire({title,text:'Please keep this window open.',allowOutsideClick:false,allowEscapeKey:false,didOpen:()=>Swal.showLoading()}); },
  close() { if(Swal.isVisible())Swal.close(); },
  validation(form) {
    const invalid=form.querySelector(':invalid');
    if(!invalid)return true;
    invalid.focus();
    Swal.fire({icon:'warning',title:'Check the highlighted field',text:invalid.validationMessage||'Please complete all required fields.',confirmButtonColor:'#f59e0b'});
    return false;
  },
  escape(value){const element=document.createElement('span');element.textContent=String(value??'');return element.innerHTML;}
};
function toast(message,icon='success'){if(icon==='success'&&Date.now()-(window.__lastApiErrorAt||0)<800)return;return Alerts.toast(message,icon);}
function confirmAction(title,text,confirmText){return Alerts.confirm(title,text,confirmText);}
function showLoading(title){return Alerts.loading(title);}
function closeLoading(){return Alerts.close();}
function showError(message,errors){return Alerts.error(message,errors);}
document.addEventListener('api:error',event=>{window.__lastApiErrorAt=Date.now();const error=event.detail;if(!Swal.isLoading())Alerts.toast(error.message,'error');});
