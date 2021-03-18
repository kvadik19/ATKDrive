let tick = 0;		// Timeout handler/
let bodyIn = document.querySelector('.tabContent.shown .qw_recv');
let bodyOut = document.querySelector('.tabContent.shown .qw_send');
let keyItems = document.querySelectorAll('#keySelect li');

let subSwitch = function(tab) {
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

let showQRY = function(host, query) {
		if ( query.code ) {
			let code = host.querySelector('.qwHdr code');
			code.innerHTML = '';
			code.innerText = query.code;
		}
		if ( query.data ) {
			let data = host.querySelector('.qw_data');
			data.innerHTML = '';
			data.appendChild( toDOM( query.data) );
		}
	};

let toDOM = function(val, key) {
		let div = createObj('div',{'className':'domItem'});
		if ( val.constructor.toString().match(/Array/) ) {
			div.innerHTML = '<span class="keyName">'+key+'</span>:';
			let content = createObj('div',{'className':'domItem array'});
			content.appendChild( toDOM( val[0] ));
			if ( val.length > 1 ) content.appendChild(createObj('div',{'className':'domItem same','innerText':'<--->',
							'title':'Подразумевается что массив ['+key+'] содержит равнозначные по типу и структуре элементы' }));
			div.appendChild(content);
		} else if ( val.constructor.toString().match(/Object/) ) {
			let content = createObj('div',{'className':'object'});
			if ( key ) {
				div.innerHTML = '<span class="keyName">'+key+'</span>:';
				content.className += ' domItem';
			}
			Object.keys(val).forEach( k=>{
					content.appendChild( toDOM( val[k], k) );
				});
			div.appendChild(content);
		} else {
			div.className += ' value';
			div.innerHTML = '<span class="keyVal">'+val+'</span>';
			if ( key ) div.innerHTML = '<span class="keyName">'+key+'</span>:<span class="keyVal">'+val+'</span>';
		}
		return div;
	};

let dispatch = {		// Switching between Tabs/subTabs dispatcher
		display: function() {
				let type = document.querySelector('.tabContent.shown .subTabs').dataset.type;
				let method = document.querySelector('.tabContent.shown .subTab.active').dataset.type;
				bodyIn = document.querySelector('.tabContent.shown .qw_recv');
				bodyOut = document.querySelector('.tabContent.shown .qw_send');
				bodyOut.onclick = function(e) {		// Deselect JSONs
						if ( e.path.findIndex( i =>{ 
										return ( i.nodeType === 1 && (i.matches('.jsonItem') || i.type === 'button') ) 
									}) < 0 ) {
							document.querySelectorAll('.jsonItem').forEach( i =>{ i.className = i.className.replace(/\s*active/g,'')});
							btnActivate();
						}
					};
				keyTool.init();
				this[type][method]();
			},
		ext: {
				read: function() {
						return true;
					},
				write: function() {
						console.log('Draw Write');
						return true;
					}
			},
		int: {
				rw: function() {
						console.log('Draw Read/Write');
						return true;
					},
			},
	};

let keyTool = {			// Add key-value floating window operations
		init: function() {
				document.querySelectorAll('#keySelect li.choosd').forEach( i =>{ i.className = i.className.replace(/\s*choosd/g,'')});
				document.querySelectorAll('#keySelect li').forEach( i =>{ i.onclick = keyTool.liChoose});
				document.querySelector('#keySelect button.esc').onclick = this.keyHide;
				document.querySelector('#keySelect button.ok').onclick = this.result;
				document.querySelector('#keySelect input[type="text"]').oninput = this.inpCheck;
				document.querySelector('#keySelect button.ok').setAttribute('disabled',1);
			},
		keyList: document.querySelectorAll('#keySelect li'),
		panel: document.getElementById('keySelect'),
		keyHide:function() { document.getElementById('keySelect').style.display = 'none'; 
				document.documentElement.onclick = null;
				bodyOut.querySelector('button[data-action="key"]').removeAttribute('disabled');
			},
		keyTrap: function(evt) {			// Click outside of keySelect window
				if ( evt.path.findIndex( i =>{ return ( i.nodeType === 1 && i.matches('.over-panel')) }) < 0 ) keyTool.keyHide();
			},
		fire: function( callbk ) {
				this.callbk = callbk;
				if ( !this.panel.style.top ) {
					this.panel.style.top = bodyOut.offsetTop+'px';
					this.panel.style.left = bodyOut.offsetLeft+'px';
				}
				document.querySelectorAll('#keySelect li.active').forEach( i =>{ i.className = i.className.replace(/\s*active/g,'')});
				document.querySelector('#keySelect input[type="text"]').value = '';
				document.documentElement.onclick = this.keyTrap;
				bodyOut.querySelector('button[data-action="key"]').setAttribute('disabled',1);
				this.panel.style.display = 'block';
			},
		result: function() {
				let key = document.querySelector('#keySelect input[type="text"]');
				let val = document.querySelector('#keySelect li.active');
				val.className = val.className.replace(/\s*choosd/g,'');		// Prevent
				val.className += ' choosd';
				if ( typeof(keyTool.callbk) === 'function' ) {
					keyTool.callbk(key.value, val.innerText);
				}
				keyTool.keyHide();
			},
		liChoose: function(evt) {
				document.querySelectorAll('#keySelect li.active').forEach( i =>{ i.className = i.className.replace(/\s*active/g,'')});
				let li = evt.target;
				let txt = document.querySelector('#keySelect input[type="text"]');
				li.className += ' active';
				if ( txt.value.replace(/\s/g,'').length === 0 
						|| document.querySelector('#keySelect li[data-name="'+txt.value+'"]') ) {
					txt.value = li.innerText;		// Not manual keyName typed
				}
				keyTool.inpCheck();
			},
		inpCheck: function(evt) {
				let txt = document.querySelector('#keySelect input[type="text"]');
				let li = document.querySelector('#keySelect li.active');
				if ( txt.value.replace(/\s/g,'').length > 0 && li ) {
					document.querySelector('#keySelect button.ok').removeAttribute('disabled');
				} else {
					document.querySelector('#keySelect button.ok').setAttribute('disabled',1);
				}
			},
	};

let jsonEdit = {			// Json elements buttons operations
		list: function(body) {
				let el = createObj('div',{'id':Date.now(),'className':'domItem jsonItem array','innerHTML':'&nbsp;','onclick':jsonSelect});
				this.place(body, el);
			},
		hash: function(body) {
				let el = createObj('div',{'className':'domItem'});
				el.appendChild(createObj('div',{'id':Date.now(),'className':'jsonItem object','innerHTML':'&nbsp;','onclick':jsonSelect}));
				this.place(body, el);
			},
		key: function(body) {
				keyTool.fire( function(key, val) {
									let el = createObj('div',{'id':Date.now(),'className':'domItem jsonItem value','onclick':jsonSelect});
									el.appendChild(createObj('span',{'className':'keyName','innerText':key}));
									el.insertAdjacentText('beforeend',':');
									el.appendChild(createObj('span',{'className':'keyVal','innerText':'$'+val}));
									jsonEdit.place(body, el);
								});
			},
		del: function(body) {
				let selected = bodyOut.querySelectorAll('.qw_data .jsonItem.active');
				if ( selected.length > 0 ) {
					selected.forEach( i =>{ try { 
												let d = i.closest('.domItem');
												d.parentNode.removeChild(d) } catch(e) {} } );
					btnActivate();
				}
			},
		place: function(body, item) {
				let qdata = body.querySelector('.qw_data');
				let selected = qdata.querySelectorAll('.jsonItem.active');
				if ( selected.length > 0 ) {
					selected.forEach( i =>{ 
							if ( i.matches('.array') ) {
								if ( i.children.length === 1 ) {
									item = createObj('div',{'className':'domItem same','innerText':'<--->',
										'title':'Подразумевается что массив содержит равнозначные по типу и структуре элементы' });
								} else if(i.children.length > 1) {
									item = null;
								}
							} else if( i.matches('.object') && !item.matches('.value') ) {
									item = null;
							}
							if ( item ) i.appendChild(item);
						} );
				} else {
					qdata.appendChild(item);
				}
			}
	};
let jsonSelect = function(e) {
		e.stopImmediatePropagation();
		let el = e.target.closest('.jsonItem');
		if ( e.shiftKey ) {
			if ( el.matches('.active') ) {
				el.className = el.className.replace(/\s*active/g,'');
			} else {
				el.className += ' active';
			}
			e.preventDefault();
		} else {
			document.querySelectorAll('.jsonItem').forEach( i =>{ i.className = i.className.replace(/\s*active/g,'')});
			el.className += ' active';
		}
		btnActivate();
	};

let btnDo = document.querySelectorAll('button.dataDo');
btnDo.forEach( bt =>{
		bt.onclick = function(e) {
				e.stopImmediatePropagation();
				let action = e.target.dataset.action;
				jsonEdit[action](bodyOut);
			};
	});

let btnActivate = function() {
		btnDo.forEach( bt =>{
				if ( bt.dataset.skip ) {
					let skip = bt.dataset.skip;
					bt.removeAttribute('disabled');
					if ( skip.match(/^\*/) ) {
						if ( skip.match(/^\*!/) ) {
							skip = skip.replace(/^\*!\s*/,'');
							if ( !bodyOut.querySelector(skip) ) bt.setAttribute('disabled', true);
						} else {
							skip = skip.replace(/^\*\s*/,'');
							if ( bodyOut.querySelector(skip) ) bt.setAttribute('disabled', true);
							
						}
					} else {
// 						if ( this.target.matches(bt.dataset.skip) ) bt.setAttribute('disabled', true);		// Tuning need
					}
				}
			});
	};

let tabs = document.querySelectorAll('.subTab:not(.fail)');
tabs.forEach( st =>{
		st.onclick = function(e) { if (e.target.matches('.active')) return;
					let tab = e.target;
						subSwitch( tab );
				};
	});

let qState = function(state) {
		if (state == 1) {
			document.getElementById('listen').disabled = true;
			document.getElementById('abort').style.display = 'initial';
		} else {
			window.clearTimeout(tick);
			flush({'code':'watchdog', 'data':{'cleanup':1}}, url);
			document.getElementById('listen').disabled = false;
			document.getElementById('abort').style.display = 'none';
			document.getElementById('tunit').innerText = 'минут';
			document.getElementById('tout').innerText = timeout;
		}
	};
document.getElementById('abort').onclick = qState;
document.getElementById('listen').onclick = function(e) {
		let btn = this;
		qState(1);
		let tstart = Date.now();
		let msg_send = {'code':'watchdog', 'data':{'timeout':period}};

		let msgGot = function(msg) {
				if ( msg.match(/^[\{\[]/) ) msg = JSON.parse(msg);
				if ( msg.data ) {
					if ( msg.data.match(/^[\{\[]/) ) msg = JSON.parse(msg.data);
					showQRY(bodyIn, msg);
					qState(0);
				} else if( Date.now() > tstart+timeout*60000 ) {
					qState(0);
				} else {
					let left = timeout*60 - Math.round( (Date.now()-tstart)/1000 );
					if (left < 60) {
						document.getElementById('tunit').innerText = 'секунд';
					} else {
						left = Math.round(left/60);
					}
					document.getElementById('tout').innerText = left;
					tick = window.setTimeout( function() { flush(msg_send, url, msgGot) }, period*1000);
				}
			};
		flush(msg_send, url, msgGot);
	};

document.getElementById('codeSync').onclick = function(e) {
		let inCode = bodyIn.querySelector('.qw_code code').innerText;
		if ( inCode ) bodyOut.querySelector('.qw_code #code').value = inCode;
	};
