#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Usage: 
       qp_install_module.py create -n <name> [<children_module>...]
       qp_install_module.py download -n <name> [<path_folder>...]
       qp_install_module.py install <name>...
       qp_install_module.py list (--installed | --available-local)
       qp_install_module.py uninstall <name>... [--and_ancestor]


Options:
    list: List all the module available
    create: Create a new module
"""

import sys
import os

try:
    from docopt import docopt
    from module_handler import ModuleHandler, get_dict_child
    from module_handler import get_l_module_descendant
    from update_README import Doc_key, Needed_key
    from qp_path import QP_SRC, QP_PLUGINS

except ImportError:
    print "source .quantum_package.rc"
    raise


def save_new_module(path, l_child):

    # ~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~ #
    # N E E D E D _ C H I L D R E N _ M O D U L E S #
    # ~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~ #

    try:
        os.makedirs(path)
    except OSError:
        print "The module ({0}) already exist...".format(path)
        sys.exit(1)

    with open(os.path.join(path, "NEEDED_CHILDREN_MODULES"), "w") as f:
        f.write(" ".join(l_child))
        f.write("\n")

    # ~#~#~#~#~#~#~ #
    # R E A D _ M E #
    # ~#~#~#~#~#~#~ #

    module_name = os.path.basename(path)

    header = "{0}\n{1}\n{0}\n".format("=" * len(module_name), module_name)

    with open(os.path.join(path, "README.rst"), "w") as f:
        f.write(header + "\n")
        f.write(Doc_key + "\n")
        f.write(Needed_key + "\n")


if __name__ == '__main__':
    arguments = docopt(__doc__)

    if arguments["list"]:

        if arguments["--installed"]:
            l_repository = [QP_SRC]
        elif arguments["--available-local"]:
            l_repository = [QP_PLUGINS]

        m_instance = ModuleHandler(l_repository)

        for module in sorted(m_instance.l_module):
            print "* {0}".format(module)

    elif arguments["create"]:
        m_instance = ModuleHandler([QP_SRC])

        l_children = arguments["<children_module>"]

        path = os.path.join(QP_SRC, arguments["<name>"])

        print "You will create the module:"
        print path

        for children in l_children:
            if children not in m_instance.dict_descendant:
                print "This module ({0}) is not a valide module.".format(children)
                print "Run `list` flag for the list of module available"
                print "Maybe you need to install some module first"
                print "Aborting..."
                sys.exit(1)

        print "You ask for this submodule:"
        print l_children

        print "You can use all the routine in this module"
        print l_children + m_instance.l_descendant_unique(l_children)

        print "This can be reduce to:"
        l_child_reduce = m_instance.l_reduce_tree(l_children)
        print l_child_reduce
        save_new_module(path, l_child_reduce)

    elif arguments["download"]:
        pass
#        d_local = get_dict_child([QP_SRC])
#        d_remote = get_dict_child(arguments["<path_folder>"])
#
#        d_child = d_local.copy()
#        d_child.update(d_remote)
#
#        name = arguments["<name>"]
#        l_module_descendant = get_l_module_descendant(d_child, [name])
#
#        for module in l_module_descendant:
#            if module not in d_local:
#                print "you need to install", module

    elif arguments["install"]:

        d_local = get_dict_child([QP_SRC])
        d_plugin = get_dict_child([QP_PLUGINS])

        d_child = d_local.copy()
        d_child.update(d_plugin)

        l_name = arguments["<name>"]

        for name in l_name:
            if name in d_local:
                print "{0} Is already installed".format(name)

        l_module_descendant = get_l_module_descendant(d_child, l_name)

        l_module_to_cp = [module for module in l_module_descendant if module not in d_local]

        if l_module_to_cp:

            print "You will need all these modules"
            print l_module_to_cp

            print "Installation...",

            for module_to_cp in l_module_to_cp:
                    src = os.path.join(QP_PLUGINS, module_to_cp)
                    des = os.path.join(QP_SRC, module_to_cp)
                    try:
                        os.symlink(src, des)
                    except OSError:
                        print "Your src directory is broken. Please remove %s" % des
                        raise
            print "Done"
            print "You can now compile as usual"

    elif arguments["uninstall"]:

        m_instance = ModuleHandler([QP_SRC])
        d_descendant = m_instance.dict_descendant

        d_local = get_dict_child([QP_SRC])
        l_name = arguments["<name>"]

        l_failed = [name for name in l_name if name not in d_local]
        if l_failed:
            print "Modules not installed:"
            for name in sorted(l_failed):
                print "* %s" % name
            sys.exit(1)
        else:
            if arguments["--and_ancestor"]:

                l_name_to_remove = l_name + [module for module in m_instance.l_module for name in l_name if name in d_descendant[module]]
                print "You will remove all of:"
                print l_name_to_remove

            else:
                l_name_to_remove = l_name

            def unlink(x):
                try:
                    os.unlink(os.path.join(QP_SRC, x))
                except OSError:
                    print "%s is a core module which can not be renmoved" % x
            map(unlink, l_name_to_remove)