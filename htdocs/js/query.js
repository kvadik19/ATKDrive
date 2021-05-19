let tick = 0;		// Timeout handler/
let bodyIn = document.querySelector('.tabContent.shown .qw_recv');
let bodyOut = document.querySelector('.tabContent.shown .qw_send');
let keyItems = document.querySelectorAll('#keySelect li');

let subSwitch = function(tab) {			// Click on subTabs
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
			let list = document.querySelector('.tabContent.shown .subTabs');
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

let showQRY = function(host, query) {			// Display incoming query received by watchdog
		let type = document.querySelector('.tabContent.shown .subTabs').dataset.type;
		let method = document.querySelector('.tabContent.shown .subTab.active').dataset.type;
		if ( query.code ) {
			let code = host.querySelector('.qwHdr code');
			code.innerHTML = '';
			code.innerText = query.code;
		}
		if ( query.data ) {
			let data = host.querySelector('.qw_data');
			data.innerHTML = '';
			data.appendChild( toDOM( query.data) );
			if ( method === 'write' ) {
				data.querySelectorAll('.keyVal').forEach( vi =>{ vi.ondblclick = keyEdit.keyvalue});
			}
		}
	};

let getVal = function(item) {		// Obtain key:value pair from DOM <div class="value">
		let value = {};
		if ( item.firstElementChild.matches('.keyVal') ) {		// Scalar value as array item
			value.val = item.firstElementChild.innerText;
		} else if (item.firstElementChild.matches('.keyName') 
					&& item.lastElementChild.matches('.keyVal') ) {		// key:scalar value pair
			value.key = item.firstElementChild.innerText;
			if ( item.dataset.name ) value.key += ';'+item.dataset.name;
			if ( item.matches('.jsonItem') ) value.key += ';%jsonItem';
			if ( item.matches('.preset') ) value.key += ';%preset';
			if ( item.matches('.bool') ) value.key += ';%bool';
			value.val= item.lastElementChild.innerText;
		} else if( item.lastElementChild ) {
			if ( item.firstElementChild.matches('.keyName') ) {		// key:object pair or just object
				value.key = item.firstElementChild.innerText;
				if ( item.dataset.name ) value.key += ';'+item.dataset.name;
				if ( item.matches('.jsonItem') ) value.key += ';%jsonItem';
				if ( item.matches('.preset') ) value.key += ';%preset';
				if ( item.matches('.bool') ) value.key += ';%bool';
			}
			value.val = fromDOM(item.lastElementChild);
		}
		return value;
	};

let fromDOM = function(node) {			// Parse DOM into JSON query definition 
		let obj;
		if ( node.className === 'domItem') node = node.firstElementChild;		// Skip extra containers
		if ( !node ) return;

		if ( node.matches('.array') ) {
			let manifest = '==manifest;';
			if ( node.matches('.jsonItem') ) manifest += '%jsonItem;';
			if ( node.matches('.preset') ) manifest += '%preset;';
			obj = [ manifest ];
			for (let nC=0; nC< node.children.length; nC++) {
				if ( node.children[nC].matches('.same') ) break;
				if ( node.children[nC].matches('.value') ) {
					let res = getVal(node.children[nC]);
					if ( res.key ) {
						let got = {};
						got[res.key] = res.val;
						obj.push(got);
					} else {
						obj.push(res.val);
					}
				} else {
					obj.push( fromDOM(node.children[nC]) );
				}
			}

		} else if ( node.matches('.object') ) {
			let manifest = '';
			if ( node.matches('.jsonItem') ) manifest += '%jsonItem;';
			if ( node.matches('.preset') ) manifest += '%preset;';
			obj  = { '==manifest':manifest };
			for (let nC=0; nC< node.children.length; nC++) {
				let res = getVal(node.children[nC]);
				obj[res.key] = res.val;
			}

		} else if ( node.matches('.value') ) {		// Probably, Helpless trigger
			let res = getVal(node);
			if ( res.key ) {
				obj = {};
				obj[res.key] = res.val;
			} else {
				obj = res.val;
			}
			
		} else if ( node.firstElementChild ) {		// Possibly exceptions trap
			obj = fromDOM(node.firstElementChild);
		}
		return obj;
	};

let fromJSON = function(obj) {			// Make JSON query from JSON query definition, ignore overload infos
		let res;
		if ( obj.constructor.toString().match(/Array/) ) {
			res = [];
			obj.forEach( ai =>{ if ( typeof(ai) === 'string' && ai.match(/^==manifest/) ) return;
								let val = fromJSON(ai);
								res.push( val ) });
		} else if ( obj.constructor.toString().match(/Object/) ) {
			res = {};
			Object.keys(obj).forEach( key =>{ 
								if ( key.match(/^==manifest/) ) return;
								let okey = keySplit(key);
								res[okey.uname] = fromJSON( obj[key] );
							});
		} else {
			res = obj;
		}
		return res;
	};

let keySplit = function( keyName ) {		// Obtain extra information from keyName
		let parts = keyName.split(';');
		let ret = { 'uname':parts.shift(), 'name':'', 'classname':'' };
		let part;
		while( part = parts.shift() ) {
			if ( part.match(/^%/) ) {
				ret.classname += ' '+ part.replace(/^%/,'');
			} else if( part.length > 0) {
				ret.name = part;
			}
		}
		return ret;
	};
	
let toDOM = function(val, key) {			// Draw JSON query definition as DOM structure
		let div = createObj('div',{'className':'domItem'});
		if ( !(val || key) ) return div;

		if ( val.constructor.toString().match(/Array/) ) {
			let manifest = '';
			if ( typeof(val[0]) === 'string' && val[0].match(/^==manifest/) ) manifest = val.shift();
			let mark = keySplit( manifest );

			let content = createObj('div',{'className':'domItem array'});
			let inner = toDOM( val[0] );
			let stub = createObj('div', {'className':'domItem same','innerText':'<--->',
							'title':'Подразумевается что массив [] содержит равнозначные по типу и структуре элементы' });
			if ( key ) {
				div.className += ' value';
				let ukey = keySplit(key);
				if ( !ukey.name ) ukey.name = ukey.uname
				let disp = ukey.uname;
				if ( translate[ukey.name] ) disp = translate[ukey.name];
				div.dataset.name = ukey.name;
				div.title = ukey.name;
				div.className += ukey.classname;

				div.innerHTML = '<span class="keyName">'+disp+'</span>:';
				content.className += mark.classname;
				content.appendChild( inner);
				if ( val.length > 1 ) {
					stub.title = stub.title.replace(/\[\]/,'['+ukey.uname+']');
					content.appendChild(stub);
				}
				div.appendChild(content);
			} else {
				div.className += mark.classname;
				div.className += ' array';
				div.appendChild(inner);
				if ( val.length > 1 ) {
					stub.title = stub.title.replace(/\[\]/,'');
					div.appendChild(stub);
				}
			}
		} else if ( val.constructor.toString().match(/Object/) ) {
			let manifest = '';
			if ( '==manifest' in val ) {
				manifest = '==manifest;'+val['==manifest'];
				delete val['==manifest'];
			}
			let mark = keySplit( manifest );
			let content = createObj('div',{'className':'object'+mark.classname});
			if ( key ) {
				let ukey = keySplit(key);
				if ( !ukey.name ) ukey.name = ukey.uname
				let disp = ukey.uname;
				if ( translate[ukey.name] ) disp = translate[ukey.name];
				div.dataset.name = ukey.name;
				div.title = ukey.name;
				div.className += ukey.classname;

				div.innerHTML = '<span class="keyName">'+disp+'</span>:';
				content.className += ' domItem';
				div.className += ' value';
			}
			Object.keys(val).forEach( k=>{
					content.appendChild( toDOM( val[k], k) );
				});
			div.appendChild(content);
		} else {
			div.className += ' value';
			div.innerHTML = '<span class="keyVal">'+val+'</span>';
			if ( key ) {
				let ukey = keySplit(key);
				if ( !ukey.name ) ukey.name = ukey.uname
				let disp = ukey.uname;
				if ( translate[ukey.name] ) disp = translate[ukey.name];
				div.dataset.name = ukey.name;
				div.title = ukey.name;
				div.className += ukey.classname;
				div.innerHTML = '<span class="keyName">'+disp+'</span>:<span class="keyVal">'+val+'</span>';
			}
		}
		return div;
	};

let dispatch = {		// Switching between Tabs/subTabs dispatcher
		getSnap: function() { 
				let box = document.querySelector('.tabContent.shown .subHolder');
				let snap = box.innerText.replace(/\s/g,'');
				box.querySelectorAll('input').forEach( i =>{ snap += i.value.replace(/\s/g,'') });
				return snap;
			},
		layout: function(type, method) {
				let bbar = document.getElementById('eCommit');
				bbar.querySelectorAll('*:not(.static)').forEach( b =>{bbar.removeChild(b)});
				let bsav = createObj('button',{'type':'button','className':'button ok','innerText':'Сохранить',
									'onclick':dispatch[type].committer, 'disabled':1});
				bbar.appendChild( bsav);
			},
		snapshot: '',
		display: function() {
				if ( !document.querySelector('.tabContent.shown') ) return;
				let type = document.querySelector('.tabContent.shown .subTabs').dataset.type;
				let method = document.querySelector('.tabContent.shown .subTab.active').dataset.type;
				document.querySelector('.tabContent.shown p.comment.addition').innerHTML = '';
				bodyIn = document.querySelector('.tabContent.shown .qw_recv.init');
				bodyOut = document.querySelector('.tabContent.shown .qw_send.init');
				if ( bodyIn ) {
					bodyIn.querySelector('.qw_code .code').innerText = '';
					bodyIn.querySelector('.qw_code .code').value = '';
					bodyIn.querySelector('.qw_data').innerHTML = '';
				}
				if (bodyOut) {
					bodyOut.querySelector('.qw_code .code').innerText = '';
					bodyOut.querySelector('.qw_code .code').value = '';
					bodyOut.querySelector('.qw_data').innerHTML = '';
					bodyOut.querySelector('.qw_body').onclick = function(e) {		// Deselect JSONs
							if ( e.path.findIndex( i =>{ 
											return ( i.nodeType === 1 
												&& (i.matches('.jsonItem') || i.type==='button' || i.matches('.codeSync')) ) 
										}) < 0 ) {
								document.querySelectorAll('.jsonItem').forEach( 
													i =>{ i.className = i.className.replace(/\s*active/g,'')});
								btnActivate();
							}
						};
						bodyOut.querySelectorAll('.codeSync').forEach( cs => { 
											cs.onclick = function(e) {	// Just transfer income `CODE` to outgoing composer
															let inCode = bodyIn.querySelector('.qw_code .code').innerText;
															if ( inCode ) bodyOut.querySelector('.qw_code input.code').value = inCode;
														}
									});
				}
				dispatch.layout(type, method);
				btnActivate();
				keyTool.init(type, method);
				this[type][method]();
			},
		int: {
				read: function() {
// 						dispatch.getSnap = function() { return bodyIn.innerText.replace(/\s/g,'') + bodyOut.innerText.replace(/\s/g,'') };
						let type = document.querySelector('.tabContent.shown .subTabs').dataset.type;
						let name = document.querySelector('.tabContent.shown .subTab.active').dataset.name;
						flush({'code':'load','data':{'name':name, 'type':type}}, document.location.href, function(resp) {
								if ( resp.match(/^[\{\[]/) ) resp = JSON.parse(resp);
								if( resp.data && resp.data.success == 1) {
									let define = resp.data;
									bodyIn.querySelector('.qw_data').appendChild( toDOM( define.qw_recv.data) );
									bodyOut.querySelector('.qw_data').appendChild( toDOM( define.qw_send.data) );

									bodyIn.querySelector('.qw_code .code').innerText = define.qw_recv.code;
									bodyOut.querySelector('.qw_code .code').value = define.qw_send.code
									document.querySelectorAll('.jsonItem').forEach( ji =>{ ji.onclick = jsonEdit.jsonSelect});
									document.querySelectorAll('.preset').forEach( pi =>{ pi.onclick = jsonEdit.rollUp});
									bodyOut.querySelectorAll('.keyName').forEach( ki =>{ ki.ondblclick = keyEdit.keyname});
									dispatch.snapshot = dispatch.getSnap();
									commitEnable();
								} else {
									console.log( resp.fail);
								}
							});
// 						dispatch.int.layout();
						return true;
					},
				write: function() {
						document.querySelector('.tabContent.shown p.comment.addition').innerHTML 
							= 'Используйте двойной шелчок на значении в получаемом запросе чтобы назначить поле в таблице шлюза';
// 						dispatch.getSnap = function() { return bodyIn.innerText.replace(/\s/g,'') + bodyOut.innerText.replace(/\s/g,'') };
						let type = document.querySelector('.tabContent.shown .subTabs').dataset.type;
						let name = document.querySelector('.tabContent.shown .subTab.active').dataset.name;
						flush({'code':'load','data':{'name':name, 'type':type}}, document.location.href, function(resp) {
								if ( resp.match(/^[\{\[]/) ) resp = JSON.parse(resp);
								if( resp.data && resp.data.success == 1) {
									let define = resp.data;
									bodyIn.querySelector('.qw_data').appendChild( toDOM( define.qw_recv.data) );
									bodyOut.querySelector('.qw_data').appendChild( toDOM( define.qw_send.data) );

									bodyIn.querySelector('.qw_code .code').innerText = define.qw_recv.code;
									bodyOut.querySelector('.qw_code .code').value = define.qw_send.code
									bodyOut.querySelectorAll('.jsonItem').forEach( ji =>{ ji.onclick = jsonEdit.jsonSelect});
									bodyOut.querySelectorAll('.preset').forEach( pi =>{ pi.onclick = jsonEdit.rollUp});
									bodyOut.querySelectorAll('.keyName').forEach( ki =>{ ki.ondblclick = keyEdit.keyname});
									bodyIn.querySelectorAll('.keyVal').forEach( vi =>{ vi.ondblclick = keyEdit.keyvalue});
									dispatch.snapshot = dispatch.getSnap();
									commitEnable();
								} else {
									console.log( resp.fail);
								}
							});
// 						dispatch.int.layout();
						return true;
					},
				committer: function(evt) {
						let name = document.querySelector('.tabContent.shown .subTab.active').dataset.name;
						let type = document.querySelector('.tabContent.shown .subTabs').dataset.type;
						let formData = {'name': name,
										'type': type,
										'qw_recv':{'code':bodyIn.querySelector('.qw_code .code').innerText,
												'data':fromDOM( bodyIn.querySelector('.qw_data'))},
										'qw_send':{'code':bodyOut.querySelector('.qw_code .code').value,
												'data':fromDOM( bodyOut.querySelector('.qw_data'))}
										};
						flush({'code':'commit','data':formData}, document.location.href, function(resp) {
								if ( resp.match(/^[\{\[]/) ) resp = JSON.parse(resp);
								if ( resp.fail ) {
									alert(resp.fail);
								} else if( resp.data.success == 1) {
									dispatch.snapshot = dispatch.getSnap();
									commitEnable();
								}
							});
					}
			},
		ext: {
				rw: function() {
						let type = document.querySelector('.tabContent.shown .subTabs').dataset.type;
						let name = document.querySelector('.tabContent.shown .subTab.active').dataset.name;
						flush({'code':'load','data':{'name':name, 'type':type}}, document.location.href, function(resp) {
								if ( resp.match(/^[\{\[]/) ) resp = JSON.parse(resp);
								if( resp.data && resp.data.success == 1) {
									document.querySelectorAll('code.pageurl').forEach( c =>{ 
															c.innerText = document.location.origin+'/'+name });
									let define = resp.data;
									bodyOut.querySelector('.qw_code .code').value = define.qw_init.qw_send.code

									let domsend = toDOM( define.qw_init.qw_send.data);
									domsend.querySelectorAll('div').forEach( d =>{		// External query type specific settings
												d.className = d.className.replace(/\s*jsonItem/g,'');		// Prevent
												d.className += ' jsonItem';
											});
									bodyOut.querySelector('.qw_data').appendChild( domsend );

									let domrecv = toDOM( define.qw_init.qw_recv.data);
									domrecv.querySelectorAll('div.value').forEach( d =>{		// External query type specific settings
												if ( d.querySelector('span.keyName') ) {
													let match = d.querySelector('span.keyName').innerText.match(/ <= ([^<^=]+)$/);
													if ( match ) {
														d.title = match[1];
													}
												}
// 												if ( d.dataset.name ) {		// Reset key names to originals
// 													d.querySelectorAll('span.keyName').forEach( s =>{
// 																s.innerText = d.dataset.name});
// 												}
												d.querySelectorAll('span.keyVal').forEach( s =>{
																	let key = s.innerText.replace(/^\$/,'');
																	if ( translate[key] ) {
																		s.innerText = '$'+translate[key];
																	}
																});
											});
									bodyIn.querySelector('.qw_code .code').value = define.qw_init.qw_recv.code
									bodyIn.querySelector('.qw_data').appendChild( domrecv );

									bodyOut.querySelectorAll('.jsonItem').forEach( ji =>{ ji.onclick = jsonEdit.jsonSelect});
									bodyOut.querySelectorAll('.preset').forEach( pi =>{ pi.onclick = jsonEdit.rollUp});
									bodyOut.querySelectorAll('.keyName').forEach( ki =>{ ki.ondblclick = keyEdit.keyname});
									bodyIn.querySelectorAll('.keyVal').forEach( vi =>{ vi.ondblclick = dispatch.ext.valAssign});
									dispatch.snapshot = dispatch.getSnap();
									commitEnable();
								} else {
									console.log( resp.fail);
								}
							});
						return true;
					},
				valAssign:function(evt) {
						let qcode = bodyIn.querySelector('.qw_code .code').value;
						if ( ('qdata' in keyTool.preset) && keyTool.preset.qdata.code === qcode ) {
							let keyVal = evt.target;
							let div = keyVal.closest('.value');
							keyTool.set( { info:div, value:keyVal.innerText, items:['query'], valuesOnly: true,
											head:'Выберите значение переменной <code>'+div.dataset.name+'</code>'})
									.fire( function(key, val) {
												let fldName = val.dataset.name;
												if ( dict[val.dataset.dict] ) {			// See `const dict`
													recoder.assign( {dict:val.dataset.dict, host:keyVal} );
												} else if ( fldName.length > 0 ) {
													keyVal.innerText = '$'+fldName;
												}
												let upper = div.parentNode.closest('.domItem[data-name]');
												val.stack.forEach( un =>{
																	if ( !upper ) return;
																	let key = upper.querySelector('span.keyName');
																	key.innerText = upper.dataset.name +' <= $'+un;
																	upper = upper.parentNode.closest('.domItem[data-name]');
																});
												commitEnable();
											} );
						} else {
							alert('Чтобы присвоить значения переменным,\n'
									+'нужно получить данные от сервера.\n'
									+'Выполните настроечный запрос');
						}
					},
				committer: function(evt) {
						let name = document.querySelector('.tabContent.shown .subTab.active').dataset.name;
						let type = document.querySelector('.tabContent.shown .subTabs').dataset.type;
						let formData = {'name': name,
										'type': type,
										'init': { 'qw_recv':{'code':bodyIn.querySelector('.qw_code .code').value,
															'data':fromDOM( bodyIn.querySelector('.qw_data'))},
												'qw_send':{'code':bodyOut.querySelector('.qw_code .code').value,
															'data':fromDOM( bodyOut.querySelector('.qw_data'))}
												},
										'ajax': [],
										};
						let ajax = document.querySelectorAll('.tabContent.shown .qw_talks.ajax');
						for ( let aN=0; aN<ajax.length; aN++) {
							let send = ajax[aN].querySelector('.message.qw_send');
							let recv = ajax[aN].querySelector('.message.qw_recv');
							if ( recv.querySelector('.qw_code .code') && send.querySelector('.qw_code .code') ) {
								formData.ajax.push({ 'qw_recv':{'code':recv.querySelector('.qw_code .code').value,
																'data':fromDOM( recv.querySelector('.qw_data'))},
													'qw_send':{'code':send.querySelector('.qw_code .code').value,
																'data':fromDOM( send.querySelector('.qw_data'))}
													});
							}
						}

						flush({'code':'commit','data':formData}, document.location.href, function(resp) {
								if ( resp.match(/^[\{\[]/) ) resp = JSON.parse(resp);
								if ( resp.fail ) {
									alert(resp.fail);
								} else if( resp.data.success == 1) {
									dispatch.snapshot = dispatch.getSnap();
									commitEnable();
								}
							});
					}
			},
	};

let keyTool = {			// Add key-value floating window operations
		panel: document.getElementById('keySelect'),
		keyList: document.querySelectorAll('#keySelect li'),
		preset:{},
		init: function( tgtType, tgtMethod ) {
				this.panel.querySelectorAll('li').forEach( li =>{ li.onclick = keyTool.liChoose;
																	li.ondblclick = keyTool.result });
				this.panel.querySelector('button.esc').onclick = this.keyHide;
				this.panel.querySelector('button.ok').onclick = this.result;
				this.panel.querySelector('input#keyName').oninput = this.inpCheck;
				this.panel.querySelector('button.ok').setAttribute('disabled',1);
				Object.keys(this.preset).forEach( k =>{ delete( this.preset[k] ) });
				this.panel.querySelector('#bool_cond').onfocus = this.condSelector;
				this.panel.querySelector('#bool_dict').onclick = this.valSelector;
				return this;
			},
		valSelector:function(evt) {
				let host = evt.target;
				let vbox = host.popup;
				if ( !vbox ) {
					vbox = createObj('select',{'className':'popBox','size':6,'style.display':'none',
									'onblur':function() {this.style.display = 'none';keyTool.inpCheck();},
									'onchange':function() {host.previousElementSibling.value=this.value;
											keyTool.panel.querySelector('input#keyName').value=this.value;
											this.blur() 
										},
									'onfocus':function() {
											this.style.width = host.previousElementSibling.offsetWidth+'px';
											this.style.left = host.previousElementSibling.offsetLeft+'px';
											this.style.top = (host.offsetTop+host.offsetHeight+2)+'px';
											this.value = host.previousElementSibling.value;
										}
								});
					host.parentNode.appendChild(vbox);
					host.popup = vbox;
				}
				vbox.innerHTML = '';
				if ( keyTool.panel.querySelector('.qItem.value.active') ) {
					let chcd = keyTool.panel.querySelector('.qItem.value.active');
					let others = chcd.parentNode.children;
					for ( let nO=0; nO < others.length; nO++ ) {
						if ( others[nO].matches('.qItem.value[data-name]') ) {
							if ( !others[nO].lastElementChild.matches('span.keyVal') ) continue;
							vbox.add(createObj('option',{'value':'$'+others[nO].dataset.name,'innerText':others[nO].dataset.name}));
						}
					}
					vbox.size = vbox.options.length;
				}
				vbox.style.display = 'block';
				vbox.focus();
				return false;
			},
		condSelector:function(evt) {
				let host = evt.target;
				let cbox = host.popup;
				if ( !cbox ) {
					cbox = createObj('select',{'className':'popBox','size':6,'style.display':'none',
									'onblur':function() {this.style.display = 'none';keyTool.inpCheck();},
									'onchange':function() {host.value=this.value; 
											host.title=this.options[this.selectedIndex].innerText;
											keyTool.panel.querySelector('input#keyName').value=this.value;
											this.blur() 
										},
									'onfocus':function() {
											this.style.left = host.offsetLeft+'px';
											this.style.top = (host.offsetTop+host.offsetHeight+2)+'px';
											this.value = host.value;
										}
								});
					[ {'name':'Меньше или Равно','value':'<='},
						{'name':'Меньше','value':'<'},
						{'name':'Равно','value':'=='},
						{'name':'Больше','value':'>'},
						{'name':'Больше или Равно','value':'>='},
						{'name':'Не равно','value':'!='}
						].forEach( opt =>{ cbox.add(createObj('option',{'value':opt.value,'innerText':opt.name}))});
					host.parentNode.appendChild(cbox);
					host.popup = cbox;
				}		// Create selector box
				cbox.style.display = 'block';
				cbox.focus();
				return false;
			},
		set: function(param) {
				Object.keys(param).forEach( k =>{ this.preset[k] = param[k] });

				this.panel.querySelector('h').innerHTML = this.preset.head;
				this.panel.querySelectorAll('.optgroup').forEach( i =>{ i.style.display = 'none'});
				if ( !('items' in this.preset) ) return this;

				this.preset.items.forEach( it =>{ it = it.replace(/^\./g,'');
						if ( it in this.preset ) this.panel.querySelector('.optgroup.'+it+' label').innerText = this.preset[it];
						this.panel.querySelector('.optgroup.'+it).removeAttribute('style');
					} );
				let liShow = this.preset.valuesOnly ? 'none' : 'list-item';
				this.panel.querySelectorAll('li[data-list="1"]').forEach( i =>{ i.style.display = liShow });
				this.panel.querySelectorAll('li.active').forEach( li =>{ li.className = li.className.replace(/\s*active/g,'')});

				let value = '';
				if ( this.preset.value) value = this.preset.value.replace(/^\$/,'');		// Remove variable mark
				let divQuery = this.panel.querySelector('.optgroup.query>div');
				let divList = this.panel.querySelector('.optgroup.list');
				let divText = this.panel.querySelector('.optgroup.text');
				// Selector type specific code
				if ( this.preset.items.includes('query') ) {		// It's visible (active)?
					let qdom = toDOM( this.preset.qdata.data);
					divQuery.innerHTML = '';
					qdom.querySelectorAll('.domItem .same').forEach( di =>{ di.parentNode.removeChild(di)} );
					qdom.querySelectorAll('.domItem .value').forEach( di =>{ di.className += ' qItem inbox'
																if ( di.lastElementChild.matches('span.keyVal') ) {
																	di.onclick = keyTool.liChoose;
																	di.ondblclick = keyTool.result;
																}
															} );
					if ( this.preset.info.matches('.bool') ) {
						divText.removeAttribute('style');
						divText.querySelector('#bool').removeAttribute('style');
						divText.querySelector('input#keyName').style.display = 'none';
						divText.querySelector('label').innerHTML = 'Переменная <code>' + this.preset.info.dataset.name
									+'</code> содержит логическое значение.<br>Опишите условие истинности:';
						divText.querySelector('#bool_name').value = '';
						let parts = value.match(/^\$?\((\$[^<^>^=^!]+)([<>=!]+)([^<^>^=^!]+)\)$/);
						if ( parts ) {
							divText.querySelector('#bool_name').value = parts[1];
							divText.querySelector('#bool_cond').value = parts[2];
							divText.querySelector('#bool_val').value = parts[3].replace(/^'|'$/g, '');
							value = parts[1].replace(/^\$/,'');
						}
					}
					qdom.querySelectorAll('.domItem .value[data-name="'+value+'"]')
											.forEach( di =>{ di.className += ' active'});
					divQuery.appendChild( qdom);

				}
				if( this.preset.items.includes('list') ) {		// It's visible (active)?
					if ( this.preset.info ) {
						divList.querySelectorAll('li[data-name="'+this.preset.info.dataset.name+'"]')
										.forEach( li =>{ li.className += ' active'});
						divText.querySelector('input#keyName').value = this.preset.info.dataset.name;
						divText.querySelector('input#keyName').removeAttribute('style');
					}
				}
				if( this.preset.items.includes('text') ) divText.removeAttribute('style')		// It's visible (active)?
				return this;
			},
		keyHide:function() { keyTool.panel.style.display = 'none'; 
				document.documentElement.onclick = null;
				keyTool.panel.querySelector('input#keyName').value = '';
				if ( keyTool.preset.info ) keyTool.preset.info.className = keyTool.preset.info.className.replace(/\s*active/g,'');
				btnActivate();
			},
		keyTrap: function(evt) {			// Click outside of keySelect window
				if ( evt.path.findIndex( i =>{ return ( i.nodeType === 1 && i.matches('.over-panel')) }) < 0 ) keyTool.keyHide();
			},
		fire: function( callbk ) {
				this.callbk = callbk;

				if ( keyTool.preset.info ) keyTool.preset.info.className += ' active';
				document.documentElement.onclick = this.keyTrap;
				this.panel.querySelector('button.ok').setAttribute('disabled', 1);

				if ( !this.panel.style.top ) {			// First call, find position
					this.panel.style.top = bodyOut.offsetTop+'px';
					this.panel.style.left = bodyOut.offsetLeft+'px';
				}

				this.panel.style.display = 'block';
				this.panel.querySelectorAll('.active')
						.forEach( li =>{ let vport = li.closest('.box');
										vport.scrollTo(0,0);					// Bring selected LI into viewport
										if ( li.offsetTop > vport.clientHeight ) 
												vport.scrollTo(0, li.offsetTop - vport.clientHeight);
								});			// Process It, if exists

				let [X, Y, W, H] = [this.panel.offsetLeft, this.panel.offsetTop,
									this.panel.offsetWidth, this.panel.offsetHeight];		// Bring PANEL into viewport
				if (X < 0) { X = 20 } 
				else if (X + W > window.innerWidth) { X = window.innerWidth - W - 20 }
				if (Y < window.scrollY) { Y = window.scrollY + 20 }
				else if (Y + H > window.scrollY+window.innerHeight) { Y=window.scrollY+window.innerHeight-H-20 }
				this.panel.style.left = X+'px';
				this.panel.style.top = Y+'px';

				return this;
			},
		result: function() {
				let key = keyTool.panel.querySelector('input#keyName');
				let val = keyTool.panel.querySelector('.active') 
										|| {'innerText':'','className':''};		// NOW Allow empty value!
				if ( typeof(keyTool.callbk) === 'function' ) {
					let clone = val.cloneNode(true);
					clone.stack = [];
					if ( keyTool.preset.info && keyTool.preset.info.matches('.bool') ) {
						let name = document.getElementById('bool_name').value;
						let cond = document.getElementById('bool_cond').value;
						let val = document.getElementById('bool_val').value;
						if ( val.replace(/\s+/g,'').match(/^\d+$/ ) ) {		// IsDigit?
							val = val.replace(/\s+/g,'');
						} else if ( val.match(/^\$/ ) ) {			// Key name?
						} else {							// Character data
							val = "'"+val+"'";
						}
						clone.dataset.name = '('+name+cond+val+')';
					} else {
						let upper = val;
						while ( upper = upper.parentNode.closest('.domItem[data-name]') ) {
							clone.stack.push(upper.dataset.name);
						}
					}
					keyTool.callbk(key.value, clone );		// Pass into callback just a LI copy
				}
				keyTool.keyHide();
			},
		liChoose: function(evt) {
				keyTool.panel.querySelectorAll('.active').forEach( i =>{ i.className = i.className.replace(/\s*active/g,'')});
				let li = evt.target.closest('.inbox');
				let txt = keyTool.panel.querySelector('input#keyName');
				li.className += ' active';
				if ( txt.value.replace(/\s/g,'').length === 0 
						|| keyTool.panel.querySelector('.box *[data-name="'+txt.value+'"]') ) {		// Not manual keyName typed
					txt.value = li.innerText;
					if (li.firstElementChild) txt.value = li.firstElementChild.innerText;
				}
				let booln = keyTool.panel.querySelector('input#bool_name');
				let boolv = keyTool.panel.querySelector('input#bool_val');
				booln.value = '$'+li.innerText;
				if ( li.children.length > 0 ) {
					booln.value = '$'+li.firstElementChild.innerText;
					if ( li.lastElementChild.matches('span.keyVal')) boolv.value = li.lastElementChild.innerText;
				}
				keyTool.inpCheck();
			},
		inpCheck: function(evt) {		// Check for some of list selected
				let txt = this.panel.querySelector('input#keyName');
				let li = this.panel.querySelector('li.active') || true;		// Ignore this check - allow empty keyName
				if ( txt.value.replace(/\s/g,'').length > 0 && li ) {					// Stub for ignore list checking is being used!
					this.panel.querySelector('button.ok').removeAttribute('disabled');
				} else {
					this.panel.querySelector('button.ok').setAttribute('disabled',1);
				}
			},
	};


let keyEdit = {
		keyname: function(evt) {
				this.target = evt.target;
				let [w, h] = [evt.target.offsetWidth, evt.target.offsetHeight];
				keyEdit.preval = evt.target.innerText;
				evt.target.innerHTML = '';
				let inpt = createObj('input',{'type':'text','className':'jsonKeyEdit',
						'style.width':w+'px','style.height':h+'px',
						'value':keyEdit.preval,
						'onblur':keyEdit.killInpt,'onkeydown':keyEdit.keyOut });
				evt.target.appendChild(inpt);
				inpt.focus();
				inpt.select();
			},
		keyvalue: function(evt) {
				let keyVal = evt.target;
				let div = keyVal.closest('.value');
				keyTool.set( { info:div, value:keyVal.innerText, valuesOnly:true, items:['list'],
							head:'Выберите поле для записи', list:''})
						.fire( function(key, val) {
									let fldName = val.dataset.name;
									div.dataset.name = fldName;
									div.title = val.title;
									if ( dict[val.dataset.dict] ) {			// See `const dict`
										recoder.assign( {dict:val.dataset.dict, host:keyVal} );
									} else if ( fldName.length > 0 ) {
										keyVal.innerText = '$'+ fldName;
									}
									commitEnable();
								} );
			},
		killInpt: function(evt) {
				let host = evt.target.closest('.keyName');
				let value = evt.target.value;
				host.removeChild(evt.target);
				if ( value.replace(/\s+/g,'').length > 0) {
					host.innerText = value;
					let preset = host.closest('.preset');
					if ( preset ) {
						let keyVal = host.parentNode;
						let sel = preset.className.replace(/ +/g,'.');
						sel = '.'+sel+' .'+keyVal.className.replace(/ +/g,'.')+'[data-name="'+keyVal.dataset.name+'"] .keyName';
						bodyOut.querySelectorAll(sel).forEach( el =>{ el.innerText = value});
					}
				} else {
					host.innerText = keyEdit.preval;
				}
				commitEnable();
			},
		keyOut: function(evt) {
				if ( evt.code.match(/Enter|Tab/) ) {
					evt.preventDefault();
					evt.target.blur();
				} else if ( evt.code.match(/Escape/) ) {
					evt.target.value = keyEdit.preval;
					evt.target.blur();
				}
			}
	};

let jsonEdit = {			// Json elements buttons operations
		jsonSelect: function(e) {			// Click on composers .jsonItems
				e.stopImmediatePropagation();
				let el = e.target.closest('.jsonItem');
				if ( e.shiftKey ) {
					e.preventDefault();
					if ( el.matches('.active') ) {
						el.className = el.className.replace(/\s*active/g,'');
					} else {
						el.className += ' active';
					}
				} else {
					document.querySelectorAll('.jsonItem').forEach( i =>{ i.className = i.className.replace(/\s*active/g,'')});
					el.className += ' active';
				}
				btnActivate();
			},

		rollUp: function(evt) {		// Rollup  .jsonItem.preset divs
				if ( !evt.target.matches('.preset') ) return;
				evt.stopImmediatePropagation();
				if ( evt.target.matches('.shorten') ) {
					evt.target.className = evt.target.className.replace(/\s*shorten/g,'');
				} else {
					evt.target.className += ' shorten';
				}
			},
		list: function(body) {			// Add array
				let el = createObj('div',{'id':Date.now(),'className':'domItem jsonItem array active','innerHTML':'&nbsp;','onclick':jsonEdit.jsonSelect});
				this.place(body, el);
			},
		hash: function(body) {			// Add Object
				let el = createObj('div',{'className':'domItem'});
				el.appendChild(createObj('div',{'id':Date.now(),'className':'jsonItem object active','innerHTML':'&nbsp;','onclick':jsonEdit.jsonSelect}));
				this.place(body, el);
			},
		key: function(body) {				// Append values from users, media tables. 
				keyTool.set( { info:null, value:null, items: ['text', 'list'],
							head: 'Выберите ключ-значение', list:'Доступные значения', text:'Ключ' } )
						.fire( function(key, val) {
								let text = val.innerText.replace(/^[\s\n]+|[\s\n]+$/g,'');
								let el = createObj('div',{'id':Date.now(),'className':'domItem jsonItem value',
															'data-name':text,'onclick':jsonEdit.jsonSelect,'title':val.title});
								if ( translate[text] && text === key ) key = translate[text];
								el.appendChild(createObj('span',{'className':'keyName','innerText':key,'ondblclick':keyEdit.keyname}));
								el.insertAdjacentText('beforeend',':');
								let keyVal = createObj('span',{'className':'keyVal','innerText':text});
								if ( val.dataset.list == '1') {
									keyVal = createObj('div',
												{'className':'domItem array preset shorten','onclick': jsonEdit.rollUp});	// Unchangeable item
									let mBox = createObj('div',{'className':'domItem'});
									let mDef = createObj('div',{'className':'object media','data-name':text});
									media_keys.forEach( mk =>{	// See also const media_keys at templates/drive/query.html.ep
										let keyName = mk.name;
										let keySample = bodyOut.querySelector('.domItem.array.preset '
															+'.domItem.value.media[data-name="'
															+mk.name+'"] .keyName');	// Obtain changed name
										if ( keySample ) {
											keyName = keySample.innerText;
										} else if ( translate[mk.name] ) {
											keyName = translate[mk.name];
										}
										let mFile = createObj('div',
														{'className':'domItem value media','data-name':mk.name,'title':mk.title});
										let mName = createObj('span',
														{'className':'keyName','innerText':keyName,'ondblclick':keyEdit.keyname});
										let mVal = createObj('span',{'className':'keyVal','innerText':'$'+mk.name});
										mFile.appendChild(mName);
										mFile.insertAdjacentText('beforeend',':');
										mFile.appendChild(mVal);
										mDef.appendChild(mFile);
									});
									mBox.appendChild(mDef);
									keyVal.appendChild(mBox);
									keyVal.appendChild(createObj('div',{'className':'domItem same','innerText':'<--->',
															'title':'Подразумевается что массив ['+text
															+'] содержит равнозначные по типу и структуре элементы' }));
									el.appendChild(keyVal);
								} else if ( dict[text] ) {			// See `const dict`
									el.appendChild(keyVal);
									recoder.assign( {dict:text, host:keyVal, reverse:true} );
								} else if ( text.length > 0 ) {
									keyVal.innerText = '$'+ text;
									el.appendChild(keyVal);
								}
								jsonEdit.place(body, el);

							});
			},
		del: function(body) {
				let selected = bodyOut.querySelectorAll('.qw_data .jsonItem.active');
				if ( selected.length > 0 ) {
					selected.forEach( i =>{ try { 
												let d = i.closest('.domItem');
												let b = d.parentNode;
												b.removeChild(d);
												if ( b.firstElementChild.matches('.same') ) b.removeChild(b.firstElementChild);
												if ( b.lastChild.nodeType == 3) b.parentNode.removeChild(b);
									 		} catch(e) {} } );
					btnActivate();
				}
			},
		place: function(body, item) {
				let qdata = body.querySelector('.qw_data');
				let selected = qdata.querySelectorAll('.jsonItem.active');
				if ( selected.length > 0 ) {
					for (nI=0; nI<selected.length; nI++) { 
						let toAdd = true;
						let i = selected[nI];
						if ( i.matches('.array') ) {
							if ( item.matches('.value') ) {			// Leave just a value
								item.removeChild(item.querySelector('.keyName'));
								if (item.firstChild.nodeType === 3) item.removeChild(item.firstChild);
							}

							if ( i.children.length === 1 ) {
								item = createObj('div',{'className':'domItem same','innerText':'<--->',
									'title':'Подразумевается что массив содержит равнозначные по типу и структуре элементы' });
							} else if(i.children.length > 1) {
								toAdd = false;
							}
						} else if( i.matches('.value') && !item.matches('.value') ) {
							i.removeChild( i.lastElementChild );
						} else if( i.matches('.object') && !item.matches('.value') ) {
							toAdd = false;
						} else if( i.matches('.value') && item.matches('.value') ) {
							toAdd = false;
						}
						if ( toAdd ) {		// Append only once! (without duplicating item)
							if ( item.matches('.active') || item.querySelector('.active') ) {
								selected.forEach( 
										j =>{ j.className = j.className.replace(/\s*active/g,'')} );
							}
							i.appendChild(item);
							break;
						}
					}
				} else {
					qdata.appendChild(item);
				}
				btnActivate();
			}
	};

let recoder = {			// Assign codec table to recoding dictionary values
		assign: function(param) {
				this.reverse = false;		// Reset this param
				Object.keys(param).forEach( k =>{ this[k] = param[k] });
				this.show();
			},
		show: function() {
				let info = this.host.parentNode;
				if ( !this.panel ) {				// Create & draw setup panel, unless exists
					let bbar = createObj('div',{'className':'buttonbar'});
					bbar.appendChild(createObj('button',{'type':'buttton','className':'ok','innerText':'Ok','onclick':this.done}));
					bbar.appendChild(createObj('button',{'type':'buttton','className':'esc','innerText':'Отмена','onclick':this.done}));
					this.panel = createObj('div',{'id':'recoder','className':'over-panel',
													'style.min-width':'10em','style.position':'absolute'});
					this.panel.appendChild(createObj('h',{'style.marginBottom':'1em'}));
					let gr1 = createObj('div',{'className':'panelrow'});
					let gr2 = gr1.cloneNode(true);
					gr1.appendChild(createObj('input',{'type':'radio','id':'cod0','name':'codec','value':'0'}));
					gr1.appendChild(createObj('label',{'htmlFor':'cod0','innerText':'Записать как есть'}));
					gr2.appendChild(createObj('input',{'type':'radio','id':'cod1','name':'codec','value':'1'}));
					gr2.appendChild(createObj('label',{'htmlFor':'cod1','innerText':'Перекодировать по таблице:'}));
					this.panel.appendChild(gr1);
					this.panel.appendChild(gr2);
					this.panel.appendChild(createObj('div',{'id':'codec','className':'optgroup'}));
					this.panel.appendChild(bbar);
					document.body.appendChild(this.panel);
				}
				document.getElementById('codec').innerHTML = '';
				document.getElementById('cod0').checked = true;
				let decod = {};
				let pairs = this.host.innerText.match(/^\$\((.+)\)$/);		// Prepare predefined values
				if ( pairs ) {			// Has predefined table?
					if ( this.reverse ) {
						pairs[1].split(';').forEach( p =>{ let [dic, man] = p.split(':'); decod[dic] = man });
					} else {
						pairs[1].split(';').forEach( p =>{ let [man, dic] = p.split(':'); decod[dic] = man });
					}
					document.getElementById('cod1').checked = true;
				}
				this.panel.querySelector('h').innerHTML = info.dataset.name+' &#8212; Значение из словаря.<br>Установите соответствие:';
				let ord = Object.keys(dict[this.dict]).sort( (a,b) =>{ return dict[this.dict][a].value - dict[this.dict][b].value });
				ord.forEach( k =>{
						let dictId = dict[this.dict][k].value;
						let row = createObj('div',{'className':'panelrow rcod','data-value':dictId,'data-name':k,
													'title':'Значение = '+dictId });
						let inp = createObj('input',{'id':'rcod'+dictId,'type':'text'});
						let mod = createObj('label',{'htmlFor':'rcod'+dictId, 'innerHTML':dict[this.dict][k].title});
						if ( decod[dictId] ) inp.value = decod[dictId];		// Assign stored value
						if ( this.reverse ) {
							row.className += ' reverse';
							row.appendChild(mod);
							row.appendChild(inp);
						} else {
							row.appendChild(inp);
							row.appendChild(mod);
						}
						document.getElementById('codec').appendChild(row);
					});

				this.panel.style.display = 'block';
				let [X, Y, W, H] = [keyTool.panel.offsetLeft, keyTool.panel.offsetTop,
									this.panel.offsetWidth, this.panel.offsetHeight];
				if (X < 0) { X = 20 } 
				else if (X + W > window.innerWidth) { X = window.innerWidth - W - 20 }
				if (Y < window.scrollY) { Y = window.scrollY + 20 }
				else if (Y + H > window.scrollY+window.innerHeight) { Y=window.scrollY+window.innerHeight-H-20 }
				this.panel.style.left = X+'px';
				this.panel.style.top = Y+'px';
			},
		done: function(evt) {					// Discard/Save panel settings
				let action = evt.target.className;
				let info = recoder.host.parentNode;
				if ( action === 'ok' ) {
					let result = '$'+info.dataset.name;		// Store data `as is`
					if (recoder.panel.querySelector('[type="radio"][name="codec"]:checked').value == 1) {	// Need to reencode values
						result = '';
						recoder.panel.querySelectorAll('#codec .panelrow.rcod').forEach( r =>{
								let man = r.querySelector('input[type="text"]').value;		// Manually entered code
								let dic = r.dataset.value;						// Dictionary's code
								if ( man.replace(/\s+/g,'').length > 0 ) {		// Only filled data
									if (r.matches('.reverse')) {
										result += dic+':'+man+';';
									} else {
										result += man+':'+dic+';';
									}
								}
							});
						result = result.replace(/;$/,'');
						if ( result.length === 0) {			// Ignore unfilled codecs
							result = '$'+info.dataset.name;
						} else {
							result = '$('+result+')';
						}
					}
					recoder.host.innerText = result;
				}
				recoder.panel.style.display = 'none';
				commitEnable();
			}
	};

let btnDo = document.querySelectorAll('button.dataDo');		// Buttons for OUT message JSON composer elements
btnDo.forEach( bt =>{
		bt.onclick = function(e) {
				e.stopImmediatePropagation();
				let action = e.target.dataset.action;
				jsonEdit[action](bodyOut);
			};
	});

let commitEnable = function() {			// Main button 'Save'
		let state = dispatch.getSnap();
		if ( state != dispatch.snapshot ) {
			document.querySelector('#eCommit button.ok').removeAttribute('disabled');
		} else {
			document.querySelector('#eCommit button.ok').setAttribute('disabled', 1);
		}
	};

let btnActivate = function() {		// Buttons for OUT message JSON composer
		btnDo.forEach( bt =>{
				if ( bt.dataset.skip ) {
					let skip = bt.dataset.skip;
					bt.removeAttribute('disabled');
					let toDis = '';
					let selectors = skip.split('&&');
					selectors.forEach( ss =>{
							let selector = ss.substring(ss.indexOf('!')+1 )
							let test = bodyOut.querySelector(selector) ? true : false;
							if ( ss.match(/!/) ) test = !test;
							if ( typeof(toDis) === 'string' ) {
								toDis = test;
							} else {
								toDis = (toDis && test);
							}
						});
					if ( toDis ) bt.setAttribute('disabled', 1);
				}

			});
		commitEnable();
	};

let qState = function(state) {		// Income Awaiting service fn
		if (state == 1) {
			document.getElementById('listen').disabled = true;
			document.getElementById('abort').style.display = 'initial';
		} else {
			window.clearTimeout(tick);
			flush({'code':'watchdog', 'data':{'cleanup':1}}, url);
			document.getElementById('listen').disabled = false;
			document.getElementById('abort').style.display = 'none';
			document.getElementById('tunit').innerText = 'минут';		// Time units
			document.getElementById('tout').innerText = timeout;
		}
	};
document.getElementById('abort').onclick = qState;		// Income query listener stop
document.getElementById('listen').onclick = function(e) {		// Income query listener activate
		let btn = this;
		qState(1);
		let tstart = Date.now();
		let msg_send = {'code':'watchdog', 'data':{'period':period,'timeout':timeout}};

		let msgGot = function(msg) {
				if ( msg.match(/^[\{\[]/) ) msg = JSON.parse(msg);

				if ( msg.data ) {
					if ( typeof(msg.data) === 'string' && msg.data.match(/^[\{\[]/) ) msg = JSON.parse(msg.data);
					bodyIn.querySelector('.qw_data').innerHTML='';
					showQRY(bodyIn, msg);
					commitEnable();
					qState(0);

				} else if( Date.now() > tstart+timeout*60000 ) {
					qState(0);

				} else {
					let left = timeout*60 - Math.round( (Date.now()-tstart)/1000 );
					if (left < 60) {
						document.getElementById('tunit').innerText = 'секунд';		// Time units
					} else {
						left = Math.round(left/60);
					}
					document.getElementById('tout').innerText = left;
					tick = window.setTimeout( function() { flush(msg_send, url, msgGot) }, period*1000);
				}
			};
		flush(msg_send, url, msgGot);
	};
document.getElementById('checkload').onclick = function(e) {		// Debugging query send
		let name = document.querySelector('.tabContent.shown .subTab.active').dataset.name;
		let code = bodyOut.querySelector('.qw_code .code').innerText || bodyOut.querySelector('.qw_code .code').value;
		let data = fromJSON( fromDOM( bodyOut.querySelector('.qw_data')) );
		let form = {'code':'checkload', 'data':{'owner':name, 'code':code, 'data':data}};
		document.getElementById('checkload_bar').style.visibility = 'visible';
		flush(form, document.location.href, function(resp) {
				document.getElementById('checkload_bar').style.visibility = 'hidden';
				resp = JSON.parse(resp);
				if ( resp.fail ) {
					alert('Ошибка запроса к серверу\n'+resp.fail);
				} else {
					bodyIn.querySelector('.qw_code .code').value = resp.data.code;
					keyTool.set( { qdata: resp.data });
				}
			});
	};
