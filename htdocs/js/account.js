// Support procedures for registration/account setup pages
let comments = {
		'director': {'summary': 'Примечание',
				'detail': 'В случае, если от имени этого руководителя действует иное лицо, '
							+'также предоставляется копия доверенности (иного документа) на осуществление соответствующих '
							+'действий, заверенная его печатью '
							+'(при наличии печати) и подписанная руководителем или уполномоченным им лицом. '
							+'В случае, если указанная доверенность подписана лицом, уполномоченным руководителем, '
							+'также предоставляется копия документа, подтверждающего полномочия этого лица'
					},
		'ustav': {'summary': 'Примечание',
				'detail': 'Устав в последней редакции с учетом всех изменений и дополнений, '
							+'все страницы (страница-прошивка с отметкой налогового органа обязательна)'
				},
		'ogrn': {'summary': 'Примечание',
				'detail': 'Если организация зарегистрирована до 01.07.2002, то необходимо представить '
							+'свидетельство о внесении записи в ЕГРЮЛ об организации, созданной до 01.07.2002'
				},
		'passport': {'summary': 'Примечание',
				'detail': ''
				},
		'inn': {'summary': 'Примечание',
				'detail': ''
				},
		'stat': {'summary': 'Примечание',
				'detail': ''
				},
		'egrul': {'summary': 'Примечание',
				'detail': ''
				},
	};

let phoneFmt = function(i) {
		let pos = i.selectionStart;
		let len = i.value.length;
		i.value = i.value.replace(/\D/g,'');
		i.value = i.value.replace(/^[78]/,'+7 ');
		i.value = i.value.replace(/^9/,'+7 9');
		i.value = i.value.replace(/^\+7\s*\(?(\d{3})\)?/,'+7 ($1) ');
		i.value = i.value.replace(/^\+7\s*\(?(\d{3})\)?\s*(\d{3})([^\-])/,'+7 ($1) $2-$3');
		i.value = i.value.replace(/^\+7\s*\(?(\d{3})\)?\s*(\d{3})[\-\s](\d{2})([^\-]+)/,'+7 ($1) $2-$3-$4');
		i.value = i.value.replace(/^\+7\s*\(?(\d{3})\)?\s*(\d{3})[\-\s](\d{2})[\-\s](\d{2}).+/,'+7 ($1) $2-$3-$4');
		if ( i.value.length == len ) i.setSelectionRange(pos, pos);
	};

let rmbtn = function(e) {
		let frow = e.target.closest('.filerow');
		if ( confirm('Удалить документ\n\xAB'+frow.dataset.name+'\xBB?\n(Полное удаление будет выполнено после сохранения)') ) {
			frow.dataset.deleted = '1';
		}
	};

let fadd = function(data) {
		data.data.forEach( f =>{
				let box = document.querySelector( 'div.fileholder[data-parent="'+f.field+'"]' );
				let frow = box.querySelector('.filerow.optrow[data-name="'+f.filename+'"]');
				if (frow) frow.parentNode.removeChild(frow);
				frow = createObj('div',{'className':'filerow optrow','title':f.filename,
											'data-id':'0','data-field':f.field,'data-name':f.filename});
				frow.appendChild(createObj('a',{'href':f.url,'innerText':f.filename,'target':'_blank'}));
				if ( uid > 0) {
					frow.appendChild(createObj('input',{'type':'text','className':'form__input','data-role':'title',
														'placeholder':'Добавьте описание, если нужно'}));
				}
				frow.appendChild(createObj('button',{'type':'button','innerHTML':'&#10005;','className':'rm',
													'onclick':rmbtn } ));
				box.appendChild(frow);
			});
	};

function traceFile (host) {
	let pBar = document.getElementById(host.id+'progr');

	let to_url = host.dataset.url;
	pBar.style.backgroundImage = "url('/img/progress_bar.png')";
	pBar.style.backgroundSize = "5% 110%";
	pBar.style.backgroundRepeat = "no-repeat";
	pBar.style.backgroundPosition = "-1em center";

	let updateProgress = function(bar, value) {
							bar.style.backgroundSize = (value+10)+'% 110%';
						};

	let formData = {};			// Some special translations
	Object.keys(host.dataset).forEach( key => { formData[key] = host.dataset[key]} );

	new uploaderObject({			// Described at support.js
			file: host.files[0],
			url: to_url,
			fieldName: host.name || host.id,
			formData: formData,
			onprogress: function(percents) {
						updateProgress(pBar, percents);
					},
			
			oncomplete: function(done, res) {
				updateProgress(pBar, 100);
				setTimeout( function() {updateProgress(pBar, 0); pBar.removeAttribute('style')}, 1500 );
				let box = host.parentNode;
				if( done && res.match(/^[\{\[]/) ) {
					let data = JSON.parse(res);
					if ( data.fail ) {
						window.alert('Загрузка '+host.files[0].name+' не удалась\n'+data.fail);

					} else if(data.data.length > 0 && host.callback) {
						host.callback(data);
					}
				} else {
					window.alert('Загрузка '+host.files[0].name+' не удалась\n'+this.lastError.text);
					console.log('File '+host.files[0].name+' upload error : '+this.lastError.text);
				}
				let newFile = createObj('input',{'type':'file','id':host.id,'name':host.id,		// 'accept':host.accept, 
												'onchange': host.onchange,
												'callback': host.callback,
												'style.display':'none'
												});
				Object.keys(host.dataset).forEach( key => { newFile.dataset[key] = host.dataset[key]} );
				box.insertBefore(newFile, host);		// Reset to prevent duplicated processing
				box.removeChild(host);
			}
		});
}

document.addEventListener('DOMContentLoaded', function(e) {
	document.querySelectorAll('.filerow button.rm').forEach( b => { b.onclick = rmbtn} );
	document.getElementById('alert').onclick = function(e) {document.getElementById('alert').style.display = "none"};

	if ( document.getElementById('reset') ) {
		document.getElementById('reset').onclick = function(e) {
				document.getElementById('alert').style.display = "none";
				let formData = { 'action':'reset', 'login':document.getElementById('_email').value,'fp':getCookie('fp') };
				flush({'code':'checkin','data':formData}, document.location.origin+'/', function(resp) {
						if ( resp.match(/^[\{\[]/) ) resp = JSON.parse(resp);
						if ( resp.data.action === 'reset') {
							if (resp.data.html_code ) {
								let alrt = document.getElementById('ralert');
								if ( !alrt ) {
									alrt = createObj('div',{'id':'ralert','className':'alert','style.display':'none',
													'onclick':function(e){ alrt.style.display = 'none' }});
									document.querySelector('#main div.container').appendChild(alrt);
								}
								alrt.innerHTML = resp.data.html_code;
								alrt.style.display = 'block';
								alrt.scrollIntoView(false);
							}
						}
					});
			};
	}
	document.querySelector('input[type="tel"]').oninput = function(e) {
			if ( !e.data ) {
				phoneFmt(e.target);
			} else if ( e.data.match(/[\d\(\)\-\+]/) ) {
				phoneFmt(e.target);
			} else {
				e.preventDefault();
			}
		};
	document.querySelector('input[type="tel"]').onpaste = function(e) {
			e.target.value = e.target.value.replace(/[^+^\d]/g, '');
			phoneFmt(e.target);
		};
	document.querySelector('input[type="tel"]').onchange = function(e) {
			phoneFmt(e.target);
		};

	document.querySelector('input[type="email"]').onfocus = function(e) { e.target.className = e.target.className.replace(/\s*fail/g,'') };
	document.querySelector('input[type="email"]').onchange = function(e) {
			e.target.className = e.target.className.replace(/\s*fail/g,'');
			flush( { 'code':'checkmail', 'data':{'email':e.target.value,'fp':getCookie('fp')} }, 
						document.location.origin+document.location.pathname,
						function(res) {
								if ( res.match(/^[\{\[]/) ) {
									res = JSON.parse(res);
									if (res.code == 1) {
										e.target.value = res.data.email;
										if ( res.data.warn ) {
											let alrt = document.getElementById('alert');
											alrt.querySelector('span.email').innerText = res.data.email;
											alrt.style.display = 'block';
											alrt.scrollIntoView(false);
										}
									} else {
										e.target.className += ' fail';
									}
								}
							});
		};

	let chmodes = document.querySelectorAll('input[name="_umode"]');
	chmodes.forEach( ch =>{				// One of that must be checked!
			ch.onchange = function() {
					if ( !this.checked ) {
						let other = chmodes[0];
						if ( this.isSameNode( other) ) other = chmodes[1];
						if ( !other.checked ) other.checked = true;
					}
				};
		});

	document.getElementById('commit').onclick = function(e) {
			let inpts = document.querySelectorAll('.udata');
			let invalid;
			let formData = {'files':[],'session':session,'fp':getCookie('fp')};
			for ( nI=0; nI<inpts.length; nI++ ) {
				let ui = inpts[nI];
				if ( ui.type.match(/radio/i) ) {			// Checking order is important!
					formData[ui.name] = ui.form.elements[ui.name].value;
				} else if ( ui.type.match(/check/i) ) {
					formData[ui.name] = (formData[ui.name] ? formData[ui.name] : 0) + (ui.checked ? ui.value*1 : 0);
				} else if( ui.value.replace(/\s/g,'').length == 0 ) {
					invalid = ui;
				} else if( ui.className.match(/fail/) ) {
					invalid = ui;
				} else if( ui.type.match(/email/i) ) {
					formData[ui.id] = ui.value.toLowerCase();
				} else {
					formData[ui.id] = ui.value;
				}
			}
			if ( invalid ) {
				invalid.scrollIntoView(false);
				invalid.focus();
				return false;
			} else {
				document.querySelectorAll('.filerow').forEach( fr =>{
						let row = {};
						Object.keys(fr.dataset).forEach( k => {
								row[k] = fr.dataset[k];
							});
						let txt = fr.querySelectorAll('input[type="text"][data-role]');
						if ( txt ) {
							txt.forEach( t =>{ row[t.dataset.role] = t.value});
						}
						formData.files.push(row);
					});
				flush({'code':'commit','data':formData}, document.location.origin+document.location.pathname, function(resp) {
						if ( resp.match(/^[\{\[]/) ) resp = JSON.parse(resp);
						if ( resp.code == 1 ) {
							if ( resp.data && resp.data.html_code ) {
								let alrt = document.getElementById('ralert');
								if ( !alrt ) {
									alrt = createObj('div',{'id':'ralert','className':'alert','style.display':'none',
												'onclick':function(e) { document.location = document.location.origin+'/' }});
									document.querySelector('#main div.container').appendChild(alrt);
								}
								alrt.innerHTML = resp.data.html_code;
								alrt.style.display = 'block';
								alrt.scrollIntoView(false);
							} else {
								document.location = document.location.origin+'/';
							}
						} else {
							console.log(resp.fail);
							console.log(resp.warn);
						}
					});
			}
		};

	document.querySelectorAll('div.upload_block').forEach( b => {
			if ( comments[b.id] && comments[b.id].detail.length > 0 ) {
				let det = createObj('details',{'open': document.location.pathname.match(/reg/) });
				det.appendChild( createObj('summary',{'innerText':comments[b.id].summary}));
				det.appendChild( createObj('span',{'className':'span-title__info','innerText':comments[b.id].detail}));
				b.insertBefore(det, b.querySelector('.fileholder'));
			}
			let uploader = b.querySelector('input[type="file"]#up_'+b.id);
			if ( !uploader ) {
				uploader = createObj('input',{'type':'file','id':'up_'+b.id,'style.display':'none',		// 'accept':'image/*',
											'onchange':function() { 
														this.callback = fadd;
														this.dataset.code = 'upload';
														this.dataset.name = b.id;
														this.dataset.session = session;
														this.dataset.fp = getCookie('fp');
														this.dataset.url = document.location.origin+'/media';
														traceFile(this) }, 
												});
				b.appendChild(uploader);
			}	
			b.querySelector('button.add').onclick = function(e) {b.querySelector('input[type="file"]').click()};
		});

	if ( document.getElementById('rpwd') ) {				// Change password button
		let panel = document.getElementById('login-body');
		let mask = document.getElementById('login-body').parentNode;

		document.getElementById('rpwd').onclick = function(e) {
				e.stopImmediatePropagation();
				mask.style.display = 'block';
				mask.style.height = document.documentElement.offsetHeight+'px';
				panel.scrollIntoView(false);
			};
		mask.onclick = function(e) {
				e.stopImmediatePropagation();
				if ( !e.path.find( n =>{ return n === panel }) ) mask.style.display = 'none';
			};

		panel.querySelectorAll('input.passwd').forEach( inp => {
				let vswitch = createObj('div',{'id':'vswitch','className':'pwd-vis','innerHTML':'&nbsp;',
											'onclick':function(e){
													let sw = 0;
													let par = [
																{'cIn':'hid$','cOut':'vis','iTyp':'password'},
																{'cIn':'vis$','cOut':'hid','iTyp':'text'}
															];
													if ( e.target.className.match(/vis$/) ) sw = 1;
													panel.querySelectorAll('input.passwd').forEach( inp => {
															let b = inp.nextElementSibling;
															inp.type = par[sw].iTyp;
															b.className = b.className.replace(RegExp(par[sw].cIn),par[sw].cOut);
														});
													e.target.previousElementSibling.focus();
												}});
				inp.parentNode.appendChild(vswitch);
			});

		document.getElementById('nopwd').onclick = function(e) { mask.style.display = 'none' };
		document.getElementById('savepwd').onclick = function(e) {
				e.stopImmediatePropagation();
				let ok = ( document.getElementById('pwd').value.length > 0 
							&& document.getElementById('pwd1').value.length > 0
							&& document.getElementById('pwd2').value.length > 0 );
				ok = (ok && document.getElementById('pwd1').value === document.getElementById('pwd2').value);
				if ( ok ) {
					let formData = {'pwd':document.getElementById('pwd').value,
									'pwd1':document.getElementById('pwd1').value,
									'session':session,
									'fp':getCookie('fp')};
					flush( {'code':'rpwd','data':formData}, document.location.origin+document.location.pathname, 
						   function(resp) {
									if ( resp.match(/^[\{\[]/) ) resp = JSON.parse(resp);
									if ( resp.code === 'rpwd') {
										if ( resp.fail ) {
											alert('Сохранение не удалось!');
											console.log( resp.fail);
										} else if( resp.data.success == 1 ) {
											mask.style.display = 'none';
										} else {
											alert('Сохранение не удалось!');
											console.log( resp);
										}
									} else {
										alert('Сохранение не удалось!');
										console.log( resp);
									}
								});
				} else {
					mask.style.display = 'none';
				}
			};

	}			// Change password

	if ( document.location.search ) {
		try { history.pushState(null, null, document.location.origin+document.location.pathname) } catch(e) {};
	}
});

//	U+2715	MULTIPLICATION X	&#10005;
// 	U+2716	HEAVY MULTIPLICATION X	&#10006;
