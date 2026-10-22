vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_plugin.vim: the plugin file. Its mappings have <Plug> names and
# default keys that a user can turn off, and loading it loads no autoload
# script and not the logger, so that Bartleby adds little to the time that
# Vim takes to start. The plugin is already loaded when these tests run, so
# most of them start a separate Vim.
# License: GNU GPL 3.0
##############################################################################

const PLUGIN: string = fnamemodify(expand('<script>'), ':p:h:h')

# FUNCTION: Start a separate Vim, run the lines before before the plugin
# loads and the lines after after it, and return g:result, which the lines
# after set.
def Fresh(before: list<string>, after: list<string>): list<string>
  var script: string = tempname()
  var out: string = tempname()
  writefile(['vim9script'] + before + ['runtime plugin/bartleby.vim'] + after
    + [$'writefile(g:result, "{out}")', 'qa!'], script)
  system($'timeout 60 {v:progpath} -es -u NONE -N --cmd "set rtp+={PLUGIN},{PLUGIN}/deps/Logger" -S {script}')
  var result: list<string> = filereadable(out) ? readfile(out) : ['(no result)']
  delete(out)
  delete(script)
  return result
enddef

def Test_default_keys_map_to_plug_names(): void
  assert_equal('<Plug>(BartlebyInspector)', maparg('<leader>bi', 'n'))
  assert_equal('<Plug>(BartlebyDefine)', maparg('<leader>bd', 'x'))
  assert_true(stridx(maparg('<Plug>(BartlebyInspector)', 'n'), 'I.Toggle()') >= 0)
enddef

# FUNCTION: The lookup keys exist without an API key. A lookup then says
# what is missing, as the commands do.
def Test_lookup_keys_exist_without_an_api_key(): void
  var result: list<string> = Fresh(
    ["$BARTLEBY_MW_DICTIONARY_KEY = ''", "$BARTLEBY_MW_THESAURUS_KEY = ''",
     "g:bartleby_dictionary_api_key = ''", "g:bartleby_thesaurus_api_key = ''"],
    ['g:result = [maparg("<leader>bd", "n"), maparg("<leader>bt", "x")]'])
  assert_equal(['<Plug>(BartlebyDefine)', '<Plug>(BartlebyThesaurus)'], result)
enddef

def Test_no_mappings_keeps_the_plug_names_without_keys(): void
  var result: list<string> = Fresh(['g:bartleby_no_mappings = true'],
    ['g:result = [maparg("<leader>bi", "n"), string(stridx(maparg("<Plug>(BartlebyInspector)", "n"), "I.Toggle()") >= 0)]'])
  assert_equal(['', 'true'], result)
enddef

def Test_a_user_mapping_of_a_plug_name_frees_its_default_key(): void
  var result: list<string> = Fresh(['nmap <F5> <Plug>(BartlebyInspector)'],
    ['g:result = [maparg("<leader>bi", "n"), maparg("<leader>bz", "n"), maparg("<F5>", "n")]'])
  assert_equal(['', '<Plug>(BartlebyFocus)', '<Plug>(BartlebyInspector)'], result)
enddef

# FUNCTION: Loading the plugin only registers its autoload imports. If it
# loaded one, Vim would load that script, and the logger with it, at every
# start.
def Test_loading_the_plugin_loads_no_autoload_script(): void
  var result: list<string> = Fresh([], [
    'g:result = getscriptinfo()->filter((_, s) => !s.autoload)',
    '  ->mapnew((_, s) => s.name)->filter((_, n) => n =~# "/autoload/\\|Logger")'])
  assert_equal([], result)
enddef

# FUNCTION: The native menu waits for GUIEnter. Registered while the plugin
# loads, it would load its autoload script at every start of gVim.
def Test_the_native_menu_waits_for_gui_enter(): void
  if !has('menu')
    return
  endif
  var result: list<string> = Fresh(
    ['import "bartleby/variables/constants.vim" as CO'],
    ['var before: bool = !empty(menu_info(CO.PLUGIN_NAME))',
     'doautocmd GUIEnter',
     'g:result = [string(before), string(!empty(menu_info(CO.PLUGIN_NAME)))]'])
  assert_equal(['false', 'true'], result)
enddef

# FUNCTION: With the default settings, VimEnter loads only tty.vim, which
# decides whether a console with few colors gets the color scheme. The
# status line waits for a scrive, and the session restore for its setting.
def Test_vim_enter_loads_only_the_color_check(): void
  var result: list<string> = Fresh([], [
    'doautocmd VimEnter',
    'g:result = getscriptinfo()->filter((_, s) => !s.autoload)',
    '  ->mapnew((_, s) => s.name)->filter((_, n) => n =~# "/autoload/\\|Logger")',
    '  ->mapnew((_, n) => fnamemodify(n, ":t"))'])
  assert_equal(['tty.vim'], result)
enddef

export def RunAll(): void
  Test_default_keys_map_to_plug_names()
  Test_lookup_keys_exist_without_an_api_key()
  Test_no_mappings_keeps_the_plug_names_without_keys()
  Test_a_user_mapping_of_a_plug_name_frees_its_default_key()
  Test_loading_the_plugin_loads_no_autoload_script()
  Test_the_native_menu_waits_for_gui_enter()
  Test_vim_enter_loads_only_the_color_check()
enddef
