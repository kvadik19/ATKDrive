// Support JS for 'request' queries 
document.addEventListener('DOMContentLoaded', function() {

		let tblCols = ['orddate-dd', 'orddate-dt', 'driver', 'weight', 'total'];
		let display = document.querySelector('.report.body');
		let failure = document.querySelector('.report.fail');

		let gotData = function(resp) {			// When response received
						if ( resp.match(/^[\{\[]/) ) resp = JSON.parse(resp);
						if ( resp.fail ) {
							alert( resp.fail);
						} else {
							// Prepare to display failure or success data
							display.className = display.className.replace(/\s*hidden/g,'');
							failure.className = failure.className.replace(/\s*hidden/g,'');
							if ( resp.data.quantity > 0 ) {
								failure.className += ' hidden';
							} else {
								display.className += ' hidden';
								let period = [resp.data['begin-dd'], resp.data['end-dd']];
								failure.querySelectorAll('span').forEach( sp =>{ sp.innerText = period.shift()});
							}
							document.getElementById('totalRec').innerText = resp.data.quantity;
							document.getElementById('shownRec').innerText = resp.data.list.length;
							
							// Refresh paginator
							let pgBox = document.querySelector('ul.pagination');
							pgBox.innerHTML = '';
console.log('Create pages');
							if ( resp.data.quantity > resp.data.list.length ) {
								let pQ = Math.ceil(resp.data.quantity/resp.data.list.length);
								for ( let nP=1; nP <= pQ; nP++ ) {
									let page = createObj('li',{'className':'page-item','innerText':nP, 
											'onclick': function(evt) {let num = this.innerText*1 - 1;
															let data = collectForm();
															data.from = num*data.koldoc + 1;
															evt.stopImmediatePropagation();
console.log('Click to '+data.from);
															flush( {'code':pgBox.dataset.code,'data':data}, 
																	document.location.origin+window.realpath, gotData);
														},
											});
									pgBox.appendChild( page );
								}
							}

console.log('Update table');
							// Update list table
							let tbl = document.querySelector('#orderList tbody') || document.getElementById('orderList');
							let td;
							while ( td = tbl.querySelector('td') ) {
								tbl.removeChild( td.parentNode );			// Kill only `td' rows, leave `th'
							}
							resp.data.list.forEach( itm =>{ let row = createObj('tr',{'className':'tdata'});
									tblCols.forEach( vn =>{ let cell = createObj('td', 
																		{'data-varname':vn, 'innerText':itm[vn]});
												row.appendChild(cell);
										});
									tbl.appendChild(row);
								});
							
						}
					};			// gotData END
		let collectForm = function() {
				let formdata = {};
				document.querySelectorAll('input.udata').forEach( inp =>{
															let val = inp.value;
															if ( val.match(/^\d+$/) ) {
																val *= 1;			// Bring to a number
															} else if( inp.type === 'date') {
																val = val.replace(/\-/g,'');
															}
															formdata[inp.dataset.key] = val;
														});
				return formdata;
			};

		document.querySelectorAll('input[type="date"]').forEach( di =>{
							let defdate = di.defaultValue.match(/^(\d{1,2})\D(\d{1,2})\D(\d{4})$/);
							if ( defdate ) di.value = defdate[3]+'-'+defdate[2]+'-'+defdate[1];		// Fix <input type="date"> initial value
						});
		document.getElementById('sendquery').onclick = function() {
				let btn = this;
				let formdata = collectForm();
				let msg = {'code':btn.dataset.code,'data':formdata};
				flush(msg, document.location.origin+window.realpath, gotData);
			};
	});
