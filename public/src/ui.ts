import $ from 'jquery'
import GoldenLayout from 'golden-layout'
import Common from './common'
import Util from './util'
import View from './view'

/** UI Settings */
export interface Settings {
  rewrite: boolean,
  sequentialise: boolean,
  auto_refresh: boolean,
  colour: boolean,
  colour_cursor: boolean,
  short_share: boolean
  model: Common.Model
}

export class CerberusUI {
  /** List of existing views */
  private views: View[]
  /** Current displayed view */
  private currentView?: View
  /** Contains the div where views are located */
  private dom: JQuery<HTMLElement>
  /** UI settings */
  public settings: Settings
  /** C11 Standard in JSON */
  private std: any
  /** Godbolt default compiler */
  defaultCompiler: Common.Compiler
  /** List of compilers */
  compilers?: Common.Compiler []

  constructor (settings: Settings) {
    this.views = []          

    this.dom = $('#views');
    window.onresize = () => this.refresh()

    this.defaultCompiler = {
      id: 'clang500',
      name: 'x86-64 clang 5.0.0'
    }

    // UI settings
    this.settings = settings
    $('#cb_concrete').prop('checked', this.settings.model == Common.Model.Concrete)
    $('#cb_rewrite').prop('checked', this.settings.rewrite)
    $('#cb_sequentialise').prop('checked', this.settings.sequentialise)
    $('#cb_auto_refresh').prop('checked', this.settings.auto_refresh)
    $('#cb_colour').prop('checked', this.settings.colour)
    $('#cb_colour_cursor').prop('checked', this.settings.colour_cursor)

    // Menu bar event handlers

    // New view
    $('#new').on('click', () => {
      let title = prompt('Please enter the file name', 'source.c');
      if (title)
        this.add(new View(title, ''))
    })

    // Load File
    $('#load').on('click', () => {
      $('#file-input').trigger('click');
    })
    $('#file-input').on('change', (e) => {
      if (!(e.target instanceof HTMLInputElement) || !e.target.files) return
      let file = e.target.files[0]
      let reader = new FileReader()
      reader.onload = (e: ProgressEvent) => {
        if (e.target instanceof FileReader)
          this.add(new View(file.name, e.target.result))
      }
      reader.readAsText(file)
    })

    // Load defacto tests
    $('#load_defacto').on('click', () => {
      $('#defacto').css('visibility', 'visible')
    })

    $('#load_defacto_cancel').on('click', () => {
      $('#defacto').css('visibility', 'hidden')
    })

    $('#load_demo').on('click', () => {
      $('#demo').css('visibility', 'visible')
    })

    $('#load_demo_cancel').on('click', () => {
      $('#demo').css('visibility', 'hidden')
    })

    $('#demo .tests a').on('click', (e) => {
      const name = e.target.textContent + '.c'
      $.get('demo/'+name).done((data) => {
        $('#demo').css('visibility', 'hidden')
        this.add(new View(name, data))
        this.refresh()
      })
    })

    // Run (Execute)
    $('#random').on('click', () => this.exec (Common.ExecutionMode.Random))
    $('#exhaustive').on('click', () => this.exec (Common.ExecutionMode.Exhaustive))
    $('#interactive').on('click', () => this.interactive())

    // Pretty print elab IRs
    $('#cabs').on('click', () => this.elab ('Cabs'))
    $('#ail-ast') .on('click', () => this.elab ('Ail_AST'))
    $('#ail') .on('click', () => this.elab ('Ail'))
    $('#core').on('click', () => this.elab ('Core'))

    // Compilers
    $('#compile').on('click', () => {
      if (this.currentView)
        this.currentView.newTab('Asm')
    })

    // Share
    let update_share_link = () => {
      if (!this.currentView) return
      const url = 'http://www.cl.cam.ac.uk/~pes20/cerberus/server/#'
                + this.currentView.getEncodedState()
      if (this.settings.short_share)
        Util.shortURL(url, (url: string) => $('#sharelink').val(url))
      else
        $('#sharelink').val(url)
    }
    let update_options_share = (short_share: boolean) => {
      if (short_share) {
        $('#current-share').text('Short')
        $('#option-share').text('Long')
      } else {
        $('#current-share').text('Long')
        $('#option-share').text('Short')
      }
    }
    update_options_share (this.settings.short_share)
    $('#option-share').on('click', () => {
      this.settings.short_share = !this.settings.short_share
      update_options_share (this.settings.short_share)
      update_share_link()
    })
    $('#sharebtn').on('click', () => {
      $('#sharelink').select()
      document.execCommand('Copy')
    })
    $('#share').on('mouseover', update_share_link)

    // Settings
    $('#concrete').on('click', (e) => {
      this.settings.model =
        (this.settings.model == Common.Model.Concrete ? Common.Model.Symbolic : Common.Model.Concrete)
      $('#cb_concrete').prop('checked', this.settings.model == Common.Model.Concrete)
    })
    $('#rewrite').on('click', (e) => {
      this.settings.rewrite = !this.settings.rewrite;
      $('#cb_rewrite').prop('checked', this.settings.rewrite)
      this.getView().emit('dirty')
    })
    $('#sequentialise').on('click', (e) => {
      this.settings.sequentialise = !this.settings.sequentialise;
      $('#cb_sequentialise').prop('checked', this.settings.sequentialise)
      this.getView().emit('dirty')
    })
    $('#auto_refresh').on('click', (e) => {
      this.settings.auto_refresh = !this.settings.auto_refresh;
      $('#cb_auto_refresh').prop('checked', this.settings.auto_refresh)
    })
    $('#colour').on('click', (e) => {
      const view = this.getView()
      this.settings.colour = !this.settings.colour
      $('#cb_colour').prop('checked', this.settings.colour)
      view.emit('clear')
      view.emit('highlight')
    })
    $('#colour_cursor').on('click', (e) => {
      this.settings.colour_cursor = !this.settings.colour_cursor;
      $('#cb_colour_cursor').prop('checked', this.settings.colour_cursor)
    })

    // Preferences
    $('#preferences').on('click', () => this.getView().newTab('Preferences'))

    // Help
    $('#help').on('click', () => this.getView().newTab('Help'))

    // Implementation Defined Choices
    $('#implementation').on('click', () => this.getView().newTab('Implementation'))

    // ISO C
    $('#isoC').on('click', () => {
      window.open('http://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf')
    })

    // REMS
    $('#rems').on('click', () => {
      window.open('http://www.cl.cam.ac.uk/~pes20/rems/')
    })

    // About
    $('#about').on('click', () => {
      window.open('https://www.cl.cam.ac.uk/~pes20/cerberus/')
    })

    // Update every 2s
    window.setInterval(() => {
      if (this.settings.auto_refresh) this.elab()
    }, 2000);

    // Get standard
    $.getJSON('std.json').done((res) => this.std = res).fail(() => {
      console.log('Failing when trying to download "std.json"')
    })

    // Get list of compilers
    $.ajax({
      headers: {Accept: 'application/json'},
      url: 'https://gcc.godbolt.org/api/compilers/c',
      type: 'GET',
      success: (data, status, query) => {
        this.defaultCompiler = $.grep(data, (e: Common.Compiler) => e.id == 'cclang500')[0]
        this.compilers       = data
      }
    })
  }

  private setCurrentView(view: View) {
    if (this.currentView)
      this.currentView.hide()
    $('#current-view-title').text(view.title)
    this.currentView = view
    view.show()
  }

  private elab (lang?: string) {
    const view = this.getView()
    if (lang) view.newTab(lang)
    if (view.isDirty()) {
      this.request(Common.Elaborate(), (res: Common.ResultRequest) => {
        view.updateState(res)
        view.emit('update')
        view.emit('highlight')
        view.resetInteractive()
      })
    }
  }

  private exec (mode: Common.ExecutionMode) {
    this.request(Common.Execute(mode), (res: Common.ResultRequest) => {
      const view = this.getView()
      const exec = view.getExec()
      if (exec) exec.setActive()
      view.updateState(res)
      view.emit('updateExecution')
    })
  }

  // start interactive mode
  private interactive() {
    this.request(Common.Step(), (data: any) => {
      const view = this.getView()
      view.updateState(data.state)
      view.newInteractiveTab(data.steps)
    })
  }

  // step interactive mode
  //@ts-ignore TODO
  private step(active: any): void {
    if (active) {
      let view = this.getView()
      this.request(Common.Step(), (data: any) => {
        view.updateState(data.state)
        view.updateInteractive(active.id, data.steps)
      }, {
        lastId: view.getState().lastNodeId,
        state: active.state,
        active: active.id,
        tagDefs: view.getState().tagDefs
      })
    } else {
      console.log('error: node '+active+' unknown')
    }
  }

  private getView(): Readonly<View> {
    if (this.currentView)
      return this.currentView
    throw new Error("Panic: no view")
  }

  getSettings(): Readonly<Settings> {
    return this.settings
  }

  add (view: View) {
    this.views.push(view)
    this.dom.append(view.dom)

    let nav = $('<div class="btn">'+view.title+'</div>')
    $('#dropdown-views').append(nav)
    nav.on('click', () => this.setCurrentView(view))

    this.setCurrentView(view)
    view.getSource().refresh()
  }

  request (action: Common.Action, onSuccess: Function, interactive?: Common.InteractiveRequest) {
    const view = this.getView()
    Util.wait()
    $.ajax({
      url:  '/cerberus',
      type: 'POST',
      headers: {Accept: 'application/json'},
      data: JSON.stringify ({
        'action':  Common.string_of_action(action),
        'source':  view.getSource().getValue(),
        'rewrite': this.settings.rewrite,
        'sequentialise': this.settings.sequentialise,
        'model': Common.string_of_model(this.settings.model),
        'interactive': interactive
      }),
      success: (data, status, query) => {
        onSuccess(data);
        Util.done()
      }
    }).fail((e) => {
      console.log('Failed request!', e)
      // TODO: this looks wrong
      this.settings.auto_refresh = false
      Util.done()
    })
  }

  getSTDSection (section: string) {
    if (!this.std) return
    const locs = section.match(/\d(\.\d)*(#\d)?/)
    if (!locs) return
    let loc = locs[0].split(/#/)
    let ns = loc[0].match(/\d+/g)
    if (!ns) return
    let title = '§'
    let p = this.std
    let content = ""
    for (let i = 0; i < ns.length; i++) {
      p = p[ns[i]]
      title += ns[i] + '.'
      if (p['title'])
        content += '<h3>'+ns[i]+'. '+p['title']+'</h3>'
    }
    // if has a paragraph
    if (loc[1] && p['P'+loc[1]]) {
      title = title.slice(0,-1) + '#' + loc[1]
      content += p['P'+loc[1]]
    } else {
      let j = 1
      while (p['P'+j]) {
        content += p['P'+j] + '</br>'
        j++
      }
    }
    let div = $('<div class="std">'+content+'</div>')
    // Create footnotes
    div.append('<hr/>')
    div.children('foot').each(function(i) {
      let n = '['+(i+1)+']'
      $(this).replaceWith(n)
      div.append('<div style="margin-top: 5px;">'+n+'. '+ $(this).html()+'</div>')
    })
    div.append('<br>')
    return {title: title, data: div}
  }

  refresh() {
    this.getView().refresh()
  }

}

/*
 * UI initialisation
 */
const UI = new CerberusUI ({
  rewrite:       false,
  sequentialise: true,
  auto_refresh:  true,
  colour:        true,
  colour_cursor: true,
  short_share:   false,
  model:         Common.Model.Concrete
})

type StartupMode =
  { kind: 'default' } |
  { kind: 'permalink', config: any } |
  { kind: 'fixedlink', file: string } // TODO: maybe add settings

let mode : StartupMode = { kind: 'default' }


// Get list of defacto tests
$.get('defacto_tests.json').done((data) => {
  let div = $('#defacto_body')
  for (let i = 0; i < data.length; i++) {
    let questions = $('<ul class="questions"></ul>')
    for (let j = 0; j < data[i].questions.length; j++) {
      let q = data[i].questions[j]
      let tests = $('<ul class="tests"></ul>')
      for (let k = 0; q.tests && k < q.tests.length; k++) {
        let name = q.tests[k]
        let test = $('<li><a href="#">'+name+'</a></li>')
        test.on('click', () => {
          $.get('defacto/'+name).done((data) => {
            $('#defacto').css('visibility', 'hidden')
            UI.add(new View(name, data))
            UI.refresh()
          })
        })
        tests.append(test)
      }
      questions.append(q.question)
      questions.append(tests)
    }
    div.append($('<h3>'+data[i].section+'</h3>'))
    div.append(questions)
  }
})

// Detect if URL is a permalink
try {
  if (mode.kind === 'default') {
    const uri = document.URL.split('#')
    if (uri && uri.length > 1 && uri[1] != "") {
      const config = GoldenLayout.unminifyConfig(JSON.parse(decodeURIComponent(uri[1])))
      mode = { kind: 'permalink',
              config: config
            }
    }
  }
} catch (e) {
  console.log(e + ': impossible to parse permalink')
}

// provenance_basic_global_yx.c
// http://localhost:8080/?provenance_basic_global_yx.c&rewrite=false&sequentialise=false&model=Symbolic

// Detect if it is a fixedlink
try {
  if (mode.kind === 'default') {
    const uri = document.URL.split('?')
    if (uri && uri.length > 1 && uri[1] != "") {
      const args = uri[1].split('&')
      let title: string = ''
      args.map((arg) => {
        const param = arg.split('=')
        const toBool = (b: string) => b === 'true'
        if (param[0] && param[1]) {
          // TODO: do not change ui directly
          // Set the options in the UI
          switch(param[0]) {
            case 'sequentialise':
              UI.settings.sequentialise = toBool(param[1])
              break
            case 'rewrite':
              UI.settings.rewrite = toBool(param[1])
              break
            case 'model':
              switch (param[1]) {
                case 'concrete':
                  UI.settings.model = Common.Model.Concrete
                  break
                case 'symbolic':
                  UI.settings.model = Common.Model.Symbolic
                  break
              }
              break
          }
        } else {
          title = param[0]
        }
      })
      if (title !== '') {
        mode = { kind: 'fixedlink', file: title}
      }
    }
  }
} catch (e) {
  console.log(e + ': no file')
}

// Detect if 

// Add view
export function onLoad() {
  switch (mode.kind) {
    case 'default':
      $.get('buffer.c').done((source) => {
        UI.add(new View('example.c', source))
        UI.refresh()
      }).fail(() => {
        console.log('Failing when trying to download "buffer.c"')
      })
      break;
    case 'permalink':
      UI.add(new View(mode.config.title, mode.config.source, mode.config))
      UI.refresh()
      break;
    case 'fixedlink':
      const file = mode.file
      $.get(file).done((source) => {
        UI.add(new View(file, source))
        UI.refresh()
      }).fail(() => {
        console.log(`Failing when trying to download ${file}`)
      })
      break;
  }
}

export default UI