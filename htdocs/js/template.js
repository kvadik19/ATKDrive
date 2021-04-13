let switchWiew = function(tab) {			// Click on subTabs
		let cook = getCookie('acTab');
		let def = {};
		if ( cook ) def = JSON.parse( decodeURIComponent(cook) );

		if ( tab && tab.matches('.subTab') ) {			// Store selected subtab state
			let list = tab.parentNode;
			def[list.dataset.type] = tab.dataset.name;
			setCookie('acTab', encodeURIComponent(JSON.stringify(def)), 
						{ 'path':'/', 'domain':document.location.host,'max-age':60*60*24*365 } );
			list.querySelectorAll('.subTab').forEach( t =>{t.className = t.className.replace(/\s*active/,'')});
			tab.className += ' active';
			dispatch.display();

		} else {			// Apply stored subtab state
			let list = document.querySelector('.tmpl_list.subTabs');
			if ( def[list.dataset.type] ) {		// Have cookie?
				let tab = list.querySelector('.subTab[data-name="'+def[list.dataset.type]+'"]');
				if ( tab ) {
					list.querySelectorAll('.subTab').forEach( t =>{t.className = t.className.replace(/\s*active/,'')});
					tab.className += ' active';
					dispatch.display();
				} else {
					switchWiew(list.firstElementChild);		// Or activate first
				}
			} else {
				switchWiew(list.firstElementChild);		// Or activate first
			}
		}
	};

let dispatch = {
		display: function() {
				let tmpl = document.querySelector('.subTab.active');
				if (tmpl) {
					this.cache = '';
					document.getElementById('netaddr').innerText = '';
					document.getElementById('fileBody').innerHTML = '';
					flush({'code':'load','filename':tmpl.dataset.filename}, document.location.href, this.load );
				}
			},
		load: function(resp) {
				if ( resp.match(/^[\{\[]/) ) resp = JSON.parse(resp);
				if ( resp.fail ) {
					alert( resp.fail);
				} else if (resp.data) {
					document.getElementById('netaddr').innerText = '//'+hostname+tmpl_dir+'/'+resp.data.filename;
					dispatch.cache = resp.data.content;
					let lines = resp.data.content.split('\n');
					let line = createObj('div',{'className':'listingLine'});
					lines.forEach( l =>{ let str = line.cloneNode();
											l = l.replace(/</g,'&lt;');
											l = l.replace(/>/g,'&gt;');
											l = l.replace(/(&lt;\/?TMPL_[\w+\s]+(=\s*['"]\w*['"])?&gt;)/ig,'<span>$1</span>');
											str.innerHTML = l;
											document.getElementById('fileBody').appendChild(str);
										});
				} else {
					console.log(resp);
				}
			},
		fup: function(evt) {
				let tmpl = document.querySelector('.subTab.active');
				if ( tmpl ) {
					let fload = document.getElementById('tmpload');
					fload.dataset.name = tmpl.dataset.filename;
					fload.dataset.url = document.location.href;
					fload.callback = function(resp) { 
							if ( tmpl.dataset.filename != resp.filename ) {
								document.querySelectorAll('li.subTab.tmpl_item.active')
										.forEach( li =>{li.className = li.className.replace(/\s*active/g,'')});
								let tab = createObj('li',{'className':'subTab tmpl_item active',
															'onclick':tabClick,'title':resp.title,
															'data-name':resp.name,'data-filename':resp.filename,
															'innerHTML':resp.name+'<br>('+resp.title+')'});
								document.querySelector('ol.tmpl_list.subTabs').appendChild(tab);
							}
							dispatch.display();
						};
					fload.click();
				}
			},
		fdn: function(evt) {
				let tmpl = document.querySelector('.subTab.active');
				if (tmpl && dispatch.cache.length > 0 ) {
					let data = 'data:text/plain;charset=utf-8;base64,'+base64Encode( dispatch.cache);
					let url = window.URL.createObjectURL( dataURLtoBlob(data) );
					let link = createObj('a', {'href':url, 'download':tmpl.dataset.filename});
					link.click();
					window.URL.revokeObjectURL(url);
				}
			},
		traceFile: function(evt) {
			let host = evt.target;
			if ( host.files[0].name != host.dataset.name ) {
				if ( !confirm('Имя загружаемого файла ('+host.files[0].name
						+')\nне совпадает с именем открытого файла ('+host.dataset.name
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

			new uploaderObject({			// Described at support.js
					file: host.files[0],
					url: to_url,
					fieldName: host.dataset.name,
					formData: {'code':'upload', 'filename':host.dataset.name},
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
