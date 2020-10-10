#!/usr/bin/env python3

# reference
# https://www.electricmonk.nl/docs/dependency_resolving_algorithm/dependency_resolving_algorithm.html

import yaml
import os


class Node(object):

    def __init__(self, name):
        self.name = name
        self.edges = []

    def addEdge(self, node):
        self.edges.append(node)
