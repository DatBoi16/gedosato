#pragma once

#include "version.h"

const char* VER_NAME = "Sepia Recollections";

const unsigned VER_MAJOR = 0;
const unsigned VER_MINOR = 12;
const unsigned VER_BUILD = 1261;

const char* VER_STRING = "version 0.12.1261 built on 2014/08/20 21:03:12";

#ifdef _DEBUG
const char* MODE_STRING = "DEBUG";
#else
const char* MODE_STRING = "RELEASE";
#endif

