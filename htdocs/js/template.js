let subSwitch = function(tab) {			// Click on subTabs
		let cook = getCookie('__acTab');
		let def = {};
		if ( cook ) def = JSON.parse( cook);

		if ( tab && tab.matches('.subTab') ) {			// Store selected subtab state
			let list = tab.parentNode;
			def[list.dataset.type] = tab.dataset.name;
			setCookie('__acTab', JSON.stringify(def), 
						{ 'path':'/', 'domain':document.location.host,'max-age':60*60*24*365 } );
			list.querySelectorAll('.subTab').forEach( t =>{t.className = t.className.replace(/\s*active/,'')});
			tab.className += ' active';
			dispatch.display();

		} else {			// Apply stored subtab state
			let list = document.querySelector('.tabContent.shown .tmpl_list.subTabs');
			if ( def[list.dataset.type] ) {		// Have cookie?
				let tab = list.querySelector('.subTab[data-name="'+def[list.dataset.type]+'"]');
				if ( tab ) {
					list.querySelectorAll('.subTab').forEach( t =>{t.className = t.className.replace(/\s*active/,'')});
					tab.className += ' active';
					dispatch.display();
				} else {
					subSwitch(list.firstElementChild);		// Or activate first
				}
			} else {
				subSwitch(list.firstElementChild);		// Or activate first
			}
		}
	};

let onLoaded = function(def) { 		// When upload success
		let tab = document.querySelector('.tabContent.shown .subTab.active');
		let fname;
		if ( tab ) fname = tab.dataset.filename;
		if ( def.title ) {		// Ordinary template uploaded.
			if ( fname != def.filename ) {		// Create new tab to display it
				document.querySelectorAll('.tabContent.shown li.subTab.tmpl_item.active')
						.forEach( li =>{li.className = li.className.replace(/\s*active/g,'')});
				let tab = createObj('li',{'className':'subTab tmpl_item active',
											'onclick':tabClick,'title':def.title,
											'data-name':def.name,'data-filename':def.filename,
											'innerHTML':def.name+'<br>('+def.title+')'});
				document.querySelector('.tabContent.shown ol.tmpl_list').appendChild(tab);
				let fail = document.querySelector('.tabContent.shown .subTab.tmpl_item.fail');
				if ( fail ) fail.parentNode.removeChild(fail);
			}
			dispatch.display();
		} else {			// Just anyfile uploaded
			let box = document.querySelector('.tabContent.shown .fileBox.filelist');
			let row = createObj('div',{'className':'filerow','title':def.filename,'onclick':fileSelect});
			Object.keys(def).forEach( k=>{ row.dataset[k] = def[k] });
			row.appendChild(createObj('span',{'className':'name','innerText':def.filename}));
			row.appendChild(createObj('span',{'className':'size','innerText':def.size}));
			row.appendChild(createObj('span',{'className':'mtime','innerText':def.mtime}));
			let exist = box.querySelector('.filerow[data-filename="'+def.filename+'"]');
			if ( exist ) {
				box.replaceChild( row, exist);
			} else {
				box.appendChild( row );
			}
		}
	};
	
let fileSelect = function(evt) {
		let list = document.querySelector('.tabContent.shown ol.tmpl_list');
		let tab = list.querySelector('.subTab.active');
		let row = evt.target.closest('.filerow');
		row.parentNode.querySelectorAll('.filerow.active').forEach( r =>{ r.className = r.className.replace(/\s*active/g,'')});
		row.className += ' active';
		let param = {'code':'load','filename':row.dataset.filename,'type':list.dataset.type,
					'path':tab.dataset.filename+tab.dataset.subdir };
		if ( row.dataset.dir ) {
			param = {'code':'load','filename':row.dataset.filename,'type':list.dataset.type };
		}
		flush( param, document.location.href, dispatch.load );
	};

let dispatch = {
		display: function() {
				let tab = document.querySelector('.tabContent.shown .subTab.active');
				this.cache = '';
				let list = document.querySelector('.tabContent.shown ol.tmpl_list');
				if (tab && tab.dataset.filename || list.dataset.type === 'dir') {
					if ( list.dataset.type === 'dir' ) {
						document.querySelector('button[data-action="fdel"]').setAttribute('disabled', 1);
					} else {
						document.querySelector('button[data-action="fdel"]').removeAttribute('disabled');
					}
					flush({'code':'load','filename':tab.dataset.filename,'type':list.dataset.type}, 
							document.location.href, this.load );
				}
			},
		load: function(resp) {
				if ( resp.match(/^[\{\[]/) ) resp = JSON.parse(resp);
				if ( resp.fail ) {
					alert( resp.fail);
				} else if (resp.data) {
					if ( typeof(resp.data.content) === 'string' ) {			// Got plain file
						document.querySelector('.tabContent.shown code.filename').innerText 
								= '//'+document.location.hostname+resp.data.path+'/'+resp.data.filename;
						let box = document.querySelector('.tabContent.shown .fileBody');
						box.innerHTML = '';
						box.dataset.filename = resp.data.filename;
						dispatch.cache = resp.data.content;
						let lines = resp.data.content.split('\n');
						let line = createObj('div',{'className':'listingLine'});
						lines.forEach( l =>{ let str = line.cloneNode();
												l = l.replace(/</g,'&lt;');
												l = l.replace(/>/g,'&gt;');
												if ( resp.data.filename.match(/css$/) ) {			// Colouring syntax
													l = l.replace(/(\S+)(\s*:)/g,'<b>$1</b>$2');
												} else if ( resp.data.filename.match(/js$/) ) {			// Colouring syntax
													l = l.replace(/(function\s*[^\(\)]*\s*\([^\)]*\))/ig,'<span>$1</span>');
													l = l.replace(/\b(let|var|const)\b/ig,'<b><i>$1</i></b>');
												} else {
													l = l.replace(/(&lt;\/?TMPL_[\w+\s]+(=\s*['"]\w*['"])?&gt;)/ig,'<span>$1</span>');
												}
												str.innerHTML = l;
												box.appendChild(str);
											});
					} else if( resp.data.content.constructor.toString().match(/Array/i) ) {		// Got filelist
						document.querySelector('.tabContent.shown .netaddr').innerText = resp.data.path;
// 						document.querySelector('.tabContent.shown code.filename').innerText = '';
						let fbody = document.querySelector('.tabContent.shown .fileBody');
						let box = document.querySelector('.tabContent.shown .fileBox.filelist');
						let tab = document.querySelector('.tabContent.shown .subTab.active');
						box.innerHTML = '';
						tab.dataset.subdir = '';
						resp.data.content.forEach( ff =>{
								let row = createObj('div',{'className':'filerow','title':ff.filename,'onclick':fileSelect});
								Object.keys(ff).forEach( k=>{ row.dataset[k] = ff[k] });
								if ( ff.dir ) {
									row.className += ' dir';
									row.dataset.filename = resp.data.filename+'/'+ff.filename;
									ff.size = '';
								}
								row.appendChild(createObj('span',{'className':'name','innerText':ff.filename}));
								row.appendChild(createObj('span',{'className':'size','innerText':ff.size}));
								row.appendChild(createObj('span',{'className':'mtime','innerText':ff.mtime}));
								if ( fbody && fbody.dataset.filename === ff.filename) row.className += ' active';
								box.appendChild(row);
							});
						if ( tab.dataset.filename != resp.data.filename) {		// Skipped into subdir
							tab.dataset.subdir = resp.data.filename.replace(tab.dataset.filename, '');
							let upper = resp.data.filename.substr(0, resp.data.filename.lastIndexOf('/'));
							let row = createObj('div',{'className':'filerow dir','title':upper,'onclick':fileSelect,
													'data-filename':upper,'data-dir':'1' });
							row.appendChild(createObj('span',{'className':'name','innerText':'..'}));
							row.appendChild(createObj('span',{'className':'size','innerText':''}));
							row.appendChild(createObj('span',{'className':'mtime','innerText':''}));
							if ( box.firstElementChild ) {
								box.insertBefore( row, box.firstElementChild );
							} else {
								box.appendChild( row );
							}
						}
					}
				} else {
					console.log(resp);
				}
			},
		fup: function(evt) {
				let fname;
				let fload = document.getElementById('tmpload');
				let tab = document.querySelector('.tabContent.shown .subTab.active');
				if ( tab ) fname = tab.dataset.filename;
				fload.dataset.type = document.querySelector('.tabContent.shown ol.tmpl_list').dataset.type;
				if ( fload.dataset.type === 'dir' ) fload.dataset.path = tab.dataset.filename+tab.dataset.subdir;
				fload.dataset.filename = fname;
				fload.dataset.url = document.location.href;
				fload.callback = onLoaded;
				fload.click();
			},
		fdn: function(evt) {
				let tab = document.querySelector('.tabContent.shown .subTab.active');
				let filename = document.querySelector('.tabContent.shown .fileBody').dataset.filename;
				if ( tab && dispatch.cache.length > 0 ) {
					let data = 'data:text/plain;charset=utf-8;base64,'+base64Encode( dispatch.cache);
					let url = window.URL.createObjectURL( dataURLtoBlob(data) );
					let link = createObj('a', {'href':url, 'download':filename});
					link.click();
					window.URL.revokeObjectURL(url);
				}
			},
		fdel: function() {
				let list = document.querySelector('.tabContent.shown ol.tmpl_list');
				if ( list.type === 'dir' ) return;
				let tab = document.querySelector('.tabContent.shown .subTab.active');
				let msg = 'Вы собираетесь удалить шаблон \xAB'+tab.dataset.filename+'\xBB';
				if ( document.querySelector('.tabContent.shown ol.tmpl_list').dataset.type == 'ext') 
							msg += '\nи этим отключить URL '+document.location.origin+'/'+tab.dataset.name;
				if ( tab && confirm(msg + '?') ) {
					flush({'code':'delete','filename':tab.dataset.filename,
							'type':document.querySelector('.tabContent.shown ol.tmpl_list').dataset.type}, 
							document.location.href, 
							function( resp ) {
								if( resp.match(/^[\{\[]/) ) {
									resp = JSON.parse(resp);
									if ( resp.fail ) {
										window.alert('Удалить \xAB'+tab.dataset.filename+'\xBB не удалось\n'+resp.fail);
									} else if ( resp.data && resp.data.filename == tab.dataset.filename ) {
										let other = tab.previousElementSibling || tab.nextElementSibling;
										if ( other ) other.className += ' active';
										tab.parentNode.removeChild(tmpl);
										dispatch.display();
									} else {
										window.alert('Удаление \xAB'+tab.dataset.filename+'\xBB:\nПерезагрузим страницу');
										document.location.reload();
									}
								} else {
									window.alert('Удаление \xAB'+tab.dataset.filename+'\xBB:\n'+resp+'\nПерезагрузим страницу');
									document.location.reload();
								}
							}
						);
				}
			},
		traceFile: function(evt) {
			let host = evt.target;
			if ( host.dataset.path ) {
				host.dataset.filename = host.files[0].name;
			} else if ( host.dataset.filename != 'undefined' 
					&& host.files[0].name != host.dataset.filename ) {
				if ( !confirm('Имя загружаемого файла ('+host.files[0].name
						+')\nне совпадает с именем открытого файла ('+host.dataset.filename
						+').\nХотите завести новый шаблон?') ) return
			}

			let pBar = document.querySelector('.progressbar');

			let to_url = host.dataset.url;
			pBar.style.backgroundImage = "url('/img/progress_barg.png')";
			pBar.style.backgroundSize = '5% 110%';
			pBar.style.backgroundRepeat = 'no-repeat';
			pBar.style.backgroundPosition = '-1em center';
			pBar.style.visibility = 'visible';

			let updateProgress = function(bar, value) {
									bar.style.backgroundSize = (value+10)+'% 110%';
								};

			let formData = {'code':'upload'};
			Object.keys(host.dataset).forEach( k =>{ formData[k] = host.dataset[k]} );
			new uploaderObject({			// Described at support.js
					file: host.files[0],
					url: to_url,
					fieldName: host.dataset.filename,
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

							} else if( data.data && host.callback) {
								host.callback(data.data);
							}
						} else {
							window.alert('Загрузка '+host.files[0].name+' не удалась\n'+this.lastError.text);
							console.log('File '+host.files[0].name+' upload error : '+this.lastError.text);
						}
						let newFile = createObj('input',{'type':'file', 'id':'tmpload','style':'display:none'});
						newFile.onchange = host.onchange;
						newFile.callback = host.callback;
						Object.keys(host.dataset).forEach( key => { newFile.dataset[key] = host.dataset[key]} );
						box.insertBefore(newFile, host);		// Reset to prevent duplicated processing
						box.removeChild(host);
					}
				});
			}

	};
