let tick = 0;		// Timeout handler/
let bodyIn = document.querySelector('.tabContent.shown .qw_recv');
let bodyOut = document.querySelector('.tabContent.shown .qw_send');
let keyItems = document.querySelectorAll('#keySelect li');
let snapshot;		//
let getSnap;		// Tools for changed data check

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

let getVal = function(item) {		// Obtain key:value pair from DOM <div class="value">
		let value = {};
		if ( item.firstElementChild.matches('.keyVal') ) {		// Scalar value as array item
			value.val = item.firstElementChild.innerText;
		} else if (item.firstElementChild.matches('.keyName') 
					&& item.lastElementChild.matches('.keyVal') ) {		// key:scalar value pair
			value.key = item.firstElementChild.innerText;
			if ( item.dataset.name ) value.key += ';'+item.dataset.name;
			value.val= item.lastElementChild.innerText;
		} else if( item.lastElementChild ) {
			if ( item.firstElementChild.matches('.keyName') ) {		// key:object pair or just object
				value.key = item.firstElementChild.innerText;
				if ( item.dataset.name ) value.key += ';'+item.dataset.name;
			}
			value.val = fromDOM(item.lastElementChild);
		}
		return value;
	};

var fromDOM = function(node) {			// Parse DOM into JSON
		let obj;
		if ( node.className === 'domItem') node = node.firstElementChild;		// Skip extra containers

		if ( node.matches('.array') ) {
			obj = [];
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
			obj  = {};
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
	
let toDOM = function(val, key) {
		let div = createObj('div',{'className':'domItem'});
		if ( val.constructor.toString().match(/Array/) ) {
			let inner = toDOM( val[0] );
			let content = createObj('div',{'className':'domItem array'});
			let stub = createObj('div', {'className':'domItem same','innerText':'<--->',
							'title':'Подразумевается что массив [] содержит равнозначные по типу и структуре элементы' });
			if ( key ) {
				div.className += ' value';
				let [uname,name] = key.split(';');
				if (name) div.dataset.name = name;
				div.innerHTML = '<span class="keyName">'+uname+'</span>:';
				content.appendChild( inner);
				if ( val.length > 1 ) {
					stub.title = stub.title.replace(/\[\]/,'['+uname+']');
					content.appendChild(stub);
				}
				div.appendChild(content);
			} else {
				div.className += ' array';
				div.appendChild(inner);
				if ( val.length > 1 ) {
					stub.title = stub.title.replace(/\[\]/,'');
					div.appendChild(stub);
				}
			}
		} else if ( val.constructor.toString().match(/Object/) ) {
			let content = createObj('div',{'className':'object'});
			if ( key ) {
				let [uname,name] = key.split(';');
				if (name) div.dataset.name = name;
				div.innerHTML = '<span class="keyName">'+uname+'</span>:';
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
				let [uname,name] = key.split(';');
				if (name) div.dataset.name = name;
				div.innerHTML = '<span class="keyName">'+uname+'</span>:<span class="keyVal">'+val+'</span>';
			}
		}
		return div;
	};

let dispatch = {		// Switching between Tabs/subTabs dispatcher
		display: function() {
				let type = document.querySelector('.tabContent.shown .subTabs').dataset.type;
				let method = document.querySelector('.tabContent.shown .subTab.active').dataset.type;
				bodyIn = document.querySelector('.tabContent.shown .qw_recv');
				bodyOut = document.querySelector('.tabContent.shown .qw_send');
				if (bodyOut) {
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
						bodyOut.querySelector('.codeSync').onclick = function(e) {	// Just transfer income `CODE` to outgoing composer
								let inCode = bodyIn.querySelector('.qw_code code').innerText;
								if ( inCode ) bodyOut.querySelector('.qw_code #code').value = inCode;
							};
				}
				btnActivate();
				keyTool.init(type);
				this[type][method]();
			},
		int: {
				read: function() {
						getSnap = function() { return bodyIn.innerHTML + bodyOut.innerHTML };
						let action = document.querySelector('.tabContent.shown .subTab.active');
						flush({'code':'load','data':{'name':action.dataset.name}}, document.location.href, function(resp) {
								if ( resp.match(/^[\{\[]/) ) resp = JSON.parse(resp);
								if ( resp.fail ) {
									alert(resp.fail);
								} else if( resp.code == 1) {
									bodyIn.querySelector('.qw_data').innerHTML = '';
									bodyOut.querySelector('.qw_data').innerHTML = '';
									bodyIn.querySelector('.qw_code code').innerText = resp.data.qw_recv.code;
									bodyOut.querySelector('.qw_code #code').value = resp.data.qw_send.code
									snapshot = getSnap();
									commitEnable();
								}
							});
						dispatch.int.committer = function(e) {
								let action = document.querySelector('.tabContent.shown .subTab.active');
								let formData = {'name':action.dataset.name,
												'qw_recv':{'code':bodyIn.querySelector('.qw_code code').innerText,
														'data':fromDOM( bodyIn.querySelector('.qw_data'))},
												'qw_send':{'code':bodyOut.querySelector('.qw_code #code').value,
														'data':fromDOM( bodyOut.querySelector('.qw_data'))}
												};
								flush({'code':'commit','data':formData}, document.location.href, function(resp) {
										if ( resp.match(/^[\{\[]/) ) resp = JSON.parse(resp);
										if ( resp.fail ) {
											alert(resp.fail);
										} else if( resp.code == 1) {
											snapshot = getSnap();
											commitEnable();
										}
									});
							};
						dispatch.int.layout();
						return true;
					},
				write: function() {
						dispatch.int.committer = function(e) {};
						console.log('Draw Write');
						dispatch.int.layout();
						return true;
					},
				layout: function() {
						let bbar = document.getElementById('eCommit');
						bbar.querySelectorAll('*:not(.static)').forEach( b =>{bbar.removeChild(b)});
						let bsav = createObj('button',{'type':'button','className':'button ok','innerText':'Сохранить',
											'onclick':dispatch.int.committer, 'disabled':1});
						bbar.appendChild( bsav);
					},
				committer: function() {
					}
			},
		ext: {
				rw: function() {
						console.log('Draw Read/Write');
						return true;
					},
			},
	};

let keyTool = {			// Add key-value floating window operations
		init: function( targeType ) {
				document.querySelectorAll('#keySelect li.choosd').forEach( i =>{ i.className = i.className.replace(/\s*choosd/g,'')});
				document.querySelectorAll('#keySelect li').forEach( i =>{ i.onclick = keyTool.liChoose;
																		i.ondblclick = keyTool.result });
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
				document.querySelectorAll('#keySelect li.active').forEach( i =>{ i.className = i.className.replace(/\s*active/g,'')});
				document.querySelector('#keySelect input[type="text"]').value = '';
				document.documentElement.onclick = this.keyTrap;
				document.querySelector('#keySelect button.ok').setAttribute('disabled',1);
				bodyOut.querySelector('button[data-action="key"]').setAttribute('disabled',1);

				if ( !this.panel.style.top ) {
					this.panel.style.top = bodyOut.offsetTop+'px';
					this.panel.style.left = bodyOut.offsetLeft+'px';
				}
				this.panel.style.display = 'block';
				let [X, Y, W, H] = [this.panel.offsetLeft, this.panel.offsetTop,
									this.panel.offsetWidth, this.panel.offsetHeight];
				if (X < 0) { X = 20 } 
				else if (X + W > window.innerWidth) { X = window.innerWidth - W - 20 }
				if (Y < window.scrollY) { Y = window.scrollY + 20 }
				else if (Y + H > window.scrollY+window.innerHeight) { Y = window.scrollY+window.innerHeight - H - 20 }
				this.panel.style.left = X+'px';
				this.panel.style.top = Y+'px';
			},
		result: function() {
				let key = document.querySelector('#keySelect input[type="text"]');
				let val = document.querySelector('#keySelect li.active') 
										|| {'innerText':'','className':''};		// NOW Allow empty value!
				val.className = val.className.replace(/\s*choosd/g,'');		// Prevent
				val.className += ' choosd';
				if ( typeof(keyTool.callbk) === 'function' ) {
					keyTool.callbk(key.value, val.cloneNode(true) );		// Pass into callback just a LI copy
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
		inpCheck: function(evt) {		// Check for some of list selected
				let txt = document.querySelector('#keySelect input[type="text"]');
				let li = document.querySelector('#keySelect li.active') || true;		// Ignore this check - allow empty keyName
				if ( txt.value.replace(/\s/g,'').length > 0 && li ) {					// Stub for ignore list checking is being used!
					document.querySelector('#keySelect button.ok').removeAttribute('disabled');
				} else {
					document.querySelector('#keySelect button.ok').setAttribute('disabled',1);
				}
			},
	};


let keyEdit = {
		action: function(evt) {
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
				let el = createObj('div',{'id':Date.now(),'className':'domItem jsonItem array active','innerHTML':'&nbsp;','onclick':jsonSelect});
				this.place(body, el);
			},
		hash: function(body) {			// Add Object
				let el = createObj('div',{'className':'domItem'});
				el.appendChild(createObj('div',{'id':Date.now(),'className':'jsonItem object active','innerHTML':'&nbsp;','onclick':jsonSelect}));
				this.place(body, el);
			},
		key: function(body) {				// Append values from users, media tables
				keyTool.fire( function(key, val) {
								let text = val.innerText.replace(/^[\s\n]+|[\s\n]+$/g,'');
								let el = createObj('div',{'id':Date.now(),'className':'domItem jsonItem value',
															'data-name':text,'onclick':jsonSelect,'title':val.title});
								el.appendChild(createObj('span',{'className':'keyName','innerText':key,'ondblclick':keyEdit.action}));
								el.insertAdjacentText('beforeend',':');
								let keyVal = createObj('span',{'className':'keyVal','innerText':text});
								if ( val.dataset.list == '1') {
									keyVal = createObj('div',
												{'className':'domItem array preset shorten','onclick': jsonEdit.rollUp});	// Unchangeable item
									let mBox = createObj('div',{'className':'domItem'});
									let mDef = createObj('div',{'className':'object media','data-name':text});
									media.forEach( m =>{
										let keyName = m.name;
										let keySample = bodyOut.querySelector('.domItem.array.preset '
															+'.domItem.value.media[data-name="'
															+m.name+'"] .keyName');	// Obtain changed name
										if ( keySample ) keyName = keySample.innerText;
										let mFile = createObj('div',
														{'className':'domItem value media','data-name':m.name,'title':m.title});
										let mName = createObj('span',
														{'className':'keyName','innerText':keyName,'ondblclick':keyEdit.action});
										let mVal = createObj('span',{'className':'keyVal','innerText':'$'+m.name});
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
								} else if ( text.length > 0 ) {
									keyVal.innerText = '$'+ text;
								}
								el.appendChild(keyVal);
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
let jsonSelect = function(e) {			// Click on composers .jsonItems
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
		if ( getSnap ) {
			let state = getSnap();
			if ( state != snapshot ) {
				document.querySelector('#eCommit button.ok').removeAttribute('disabled');
			} else {
				document.querySelector('#eCommit button.ok').setAttribute('disabled', 1);
			}
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

let tabs = document.querySelectorAll('.subTab:not(.fail)');
tabs.forEach( st =>{
		st.onclick = function(e) { if (e.target.matches('.active')) return;
					let tab = e.target;
						subSwitch( tab );
				};
	});

let qState = function(state) {		// Income Awaiting service fn
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
document.getElementById('abort').onclick = qState;		// Income query listener stop
document.getElementById('listen').onclick = function(e) {		// Income query listener activate
		let btn = this;
		qState(1);
		let tstart = Date.now();
		let msg_send = {'code':'watchdog', 'data':{'period':period,'timeout':timeout}};

		let msgGot = function(msg) {
				if ( msg.match(/^[\{\[]/) ) msg = JSON.parse(msg);
				if ( msg.data ) {
					if ( typeof(msg.data) == 'string' && msg.data.match(/^[\{\[]/) ) msg = JSON.parse(msg.data);
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
