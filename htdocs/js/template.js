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
					subSwitch(list.firstElementChild);		// Or activate first
				}
			} else {
				subSwitch(list.firstElementChild);		// Or activate first
			}
		}
	};

let dispatch = {
		display: function() {
				let tmpl = document.querySelector('.subTab.active');
				if (tmpl) {
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
					let lines = resp.data.content.split('\n');
					let line = createObj('div',{'className':'listingLine'});
					lines.forEach( l =>{ let str = line.cloneNode();
											l = l.replace(/</g,'&lt;');
											l = l.replace(/>/g,'&gt;');
											l = l.replace(/(&lt;\/?TMPL_[\w+\s]+(=\s*['"]\w*['"])?&gt;)/ig,'<span>$1</span>');
// 											l = l.replace(/(&lt;\/TMPL_\w+&gt;)/ig,'<span>$1</span>');
											str.innerHTML = l;
											document.getElementById('fileBody').appendChild(str);
										});
				} else {
					console.log(resp);
				}
			}
	};
