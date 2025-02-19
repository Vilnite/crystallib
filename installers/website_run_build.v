module installers

import despiegk.crystallib.myconfig
import despiegk.crystallib.process
import despiegk.crystallib.gittools
import despiegk.crystallib.publishermod
import cli
import os
import json

pub struct Group {
	pub mut:
		users  []string
		groups []string
}

pub struct RewriteRole {
	pub mut:
		redirect map[string]string
		rewrite map[string]string
}

pub struct Acls {
	pub mut:
		users []string
		groups []string
		password string   
}

fn website_conf_repo_get(cmd &cli.Command) ?(myconfig.ConfigRoot, &gittools.GitRepo) {
	mut conf := myconfig.get(true) ?
	flags := cmd.flags.get_all_found()
	mut name := flags.get_string("repo") or {""}

	mut res := []string{}
	for mut site in conf.sites_get() {
		if site.cat == myconfig.SiteCat.web {
			if site.name.contains(name) {
				res << site.reponame()
			}
		}
	}

	if res.len == 1 {
		name = res[0]
	} else if res.len > 1 {
		sites_list(cmd) ?
		return error('Found more than 1 or website with name: $name')
	} else {
		sites_list(cmd) ?
		return error('Cannot find website with name: $name')
	}

	mut gt := gittools.new(conf.paths.code) or { return error('ERROR: cannot load gittools:$err') }
	reponame := conf.reponame(name) ?
	mut repo := gt.repo_get(name: reponame) or {
		return error('ERROR: cannot find repo: $name\n$err')
	}

	return conf, repo
}

pub fn website_develop(cmd &cli.Command) ? {
	_, repo := website_conf_repo_get(cmd) ?
	println(' - start website: $repo.path')
	process.execute_interactive('$repo.path/run.sh') ?
}

fn rewrite_config(path string,shortname string){
	println (" >> REWRITE CONFIG: $path $shortname")
}

pub fn website_build(cmd &cli.Command) ? {
	mut arg := ""
	mut use_prefix := false

	arg = cmd.flags.get_string("repo") or {""}
	use_prefix = cmd.flags.get_bool("pathprefix") or {false}

	mut conf := myconfig.get(true) ?
	mut sites := conf.sites_get()
	mut role := RewriteRole{
		redirect: map{
			"from": ""
			"to": ""
		}
		rewrite: map{
			"in": ""
			"out": ""
		}
	}

	// groups
	os.write_file('$conf.paths.publish/.groups.json', json.encode(map{
		'test': Group{}
	})) ?
	if arg.len == 0 {
		println('- Flatten all wikis')
		mut publ := publishermod.new(conf.paths.code) or { panic('cannot init publisher. $err') }
		publ.flatten()?
		println(' - build all websites')
		mut gt := gittools.new(conf.paths.code) or {
			return error('ERROR: cannot load gittools:$err')
		}
		for site in sites {
			if site.cat == myconfig.SiteCat.web {
				mut repo2 := gt.repo_get(name: site.name) or {
					return error('ERROR: cannot find repo: $site.name\n$err')
				}
				println(' - build website: $repo2.path')
				process.execute_stdout('sed -i "s/pathPrefix.*//" $repo2.path/gridsome.config.js') ?
				
				if use_prefix {
					process.execute_stdout('sed -i "s/plugins: \\\[/pathPrefix: \\\"$site.shortname\\\",\\n\\tplugins: \\\[/g" $repo2.path/gridsome.config.js') ?
					// rewrite_config("${repo2.path}/gridsome.config.js",site.shortname)
				}

				process.execute_stdout('$repo2.path/build.sh') or {process.execute_stdout('cd $repo2.path/ && git checkout gridsome.config.js') ?}

				process.execute_stdout('cd $repo2.path/ && git checkout gridsome.config.js') ?

				os.write_file('$conf.paths.publish/$site.name/.domains.json', json.encode(map{
					'domains': site.domains
				})) ?

				os.write_file('$conf.paths.publish/$site.name/.repo', json.encode(map{
					'repo':  '$repo2.addr.name'
					'alias': site.shortname
				})) ?

				os.write_file('$conf.paths.publish/$site.name/.acls.json', json.encode(Acls{})) ?

				os.write_file('$conf.paths.publish/$site.name/.roles.json', json.encode(role)) ?
			}
		}
	} else {
		_, repo := website_conf_repo_get(cmd) ?
		// be careful process stops after interactive execute
		// process.execute_interactive('$repo.path/build.sh') ?
		for site in sites {
			if site.name == repo.addr.name {
				println(' - build website: $repo.path')
				process.execute_stdout('sed -i "s/pathPrefix.*//" $repo.path/gridsome.config.js') ?

				if use_prefix {
					process.execute_stdout('sed -i "s/plugins: \\\[/pathPrefix: \\\"$site.shortname\\\",\\n\\tplugins: \\\[/g" $repo.path/gridsome.config.js') ?
				}

				process.execute_stdout('$repo.path/build.sh') ?
				process.execute_stdout('cd $repo.path/ && git checkout gridsome.config.js') ?

				os.write_file('$conf.paths.publish/$site.name/.domains.json', json.encode(map{
					'domains': site.domains
				})) ?

				os.write_file('$conf.paths.publish/$site.name/.repo', json.encode(map{
					'repo':  '$repo.addr.name'
					'alias': site.shortname
				})) ?

				os.write_file('$conf.paths.publish/$site.name/.acls.json', json.encode(Acls{})) ?
				os.write_file('$conf.paths.publish/$site.name/.roles.json', json.encode(role)) ?
				break
			}
		}
	}
}
