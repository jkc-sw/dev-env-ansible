#!/usr/bin/env python3

import argparse
import os
import yaml
from yaml import Loader

# project dir
PROJECT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))


class Role(object):

    def __init__(self, name):
        self.name = name
        self.children = []

    def __hash__(self):
        return hash(self.name)

    def __eq__(self, other):
        if isinstance(other, Role):
            return self.name == other.name
        elif isinstance(other, str):
            return self.name == other
        else:
            raise Exception(f"Cannot compare {self} with {other}")

    def __repr__(self):
        # if self.children:
        #     return f"{self.name} -> ({self.children})"
        # else:
        #     return f"{self.name}"
        return f"{self.name}"

    def __str__(self):
        return self.__repr__()

    def add_child(self, child):
        self.children.append(child)


def read_roles(path: str) -> Role:
    # read the playbook
    with open(path, 'r') as f:
        book = yaml.load(f, Loader=Loader)

    # create the node
    start = Role('playbook')
    # get the roles
    roles = []
    for sec in book:
        if 'roles' in sec:
            roles = sec['roles']

    # return if no roles to depend on
    if not roles:
        return start

    # list of roles
    role_list = os.listdir(os.path.join(PROJECT_DIR, 'roles'))

    # collect availables
    roles_available = {k: Role(k) for k in role_list}

    # search for all the nodes
    for role in role_list:

        # easy name
        meta_yml = os.path.join(PROJECT_DIR, 'roles', role, 'meta', 'main.yml')

        # read the meta files if exists
        if os.path.exists(meta_yml):
            # read the meta
            with open(meta_yml, 'r') as f:
                meta = yaml.load(f, Loader=Loader)

            # check that meta has dependencies
            if 'dependencies' in meta:
                # Add all depdencies
                for each in meta['dependencies']:
                    roles_available[role].add_child(roles_available[each])

    # create playbook node
    for role in roles:
        # add the populated roles dep
        start.add_child(roles_available[role])

    # return
    return start


def resolve_dep(node, resolved, unresolved):
    # mark them unresolved for now
    unresolved.append(node)

    # do dependencies check
    for edge in node.children:

        if edge not in resolved:
            if edge in unresolved:
                # if an edge is not resolved and marked unresolved, it means
                #   this is a circular dependencies as we should only be able
                #   to see this edge once
                raise Exception(f'Detected circular dep: {node.name} -> {node.edges}')

            # otherwise, resolve recursively
            resolve_dep(edge, resolved, unresolved)

    # store the output as resolved
    resolved.append(node)
    unresolved.remove(node)


def print_deps(node: Role, indent=0):
    print(f"{' '*indent}{node.name}")
    for e in node.children:
        print_deps(e, indent + 2)


def main():

    # create simple cli
    description = "Generate dependencies plot for ansible roles"
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument(
        '-b', '--playbook',
        default=os.path.join(PROJECT_DIR, 'playbook.yml'),
        help="The entry point playbook to search deps from"
    )
    args = parser.parse_args()

    # process raw files
    start = read_roles(args.playbook)
    print_deps(start)

    # resolve dep
    resolved = []
    unresolved = []
    resolve_dep(start, resolved, unresolved)
    # print(resolved)
    # print(unresolved)


if __name__ == "__main__":
    main()


# reference
# https://www.electricmonk.nl/docs/dependency_resolving_algorithm/dependency_resolving_algorithm.html
# Copyright © 2008-2018, Ferry Boender
#
# This document may be freely distributed, in part or as a whole, on any
# medium, without the prior authorization of the author, provided that this
# Copyright notice remains intact, and there will be no obstruction as to
# the further distribution of this document. You may not ask a fee for the
# contents of this document, though a fee to compensate for the distribution
# of this document is permitted.
#
# Modifications to this document are permitted, provided that the modified
# document is distributed under the same license as the original document
# and no copyright notices are removed from this document. All contents
# written by an author stays copyrighted by that author.
#
# Failure to comply to one or all of the terms of this license automatically
# revokes your rights granted by this license
#
# All brand and product names mentioned in this document are trademarks or
# registered trademarks of their respective holders.
