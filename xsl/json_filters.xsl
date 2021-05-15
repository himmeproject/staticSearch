<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xs="http://www.w3.org/2001/XMLSchema"
    xmlns:xd="http://www.oxygenxml.com/ns/doc/xsl"
    xmlns:j="http://www.w3.org/2005/xpath-functions"
    xmlns:math="http://www.w3.org/2005/xpath-functions/math"
    xmlns:map="http://www.w3.org/2005/xpath-functions/map"
    xmlns:hcmc="http://hcmc.uvic.ca/ns/staticSearch"
    xpath-default-namespace="http://www.w3.org/1999/xhtml"
    xmlns="http://www.w3.org/1999/xhtml"
    exclude-result-prefixes="#all"
    version="3.0">
    <xd:doc scope="stylesheet">
        <xd:desc>
            <xd:p><xd:b>Created on:</xd:b> June 26, 2019</xd:p>
            <xd:p><xd:b>Authors:</xd:b> Joey Takeda and Martin Holmes</xd:p>
            <xd:p>This transformation takes a collection of tokenized and stemmed documents (tokenized
                via the process described in <xd:a href="tokenize.xsl">tokenize.xsl</xd:a>) and creates
                a JSON file for each stemmed token. It also creates a separate JSON file for the project's
                stopwords list, for all the document titles in the collection, and for each of the filter facets.
                Finally, it creates a single JSON file listing all the stems, which may be used for glob searches.</xd:p>
        </xd:desc>
    </xd:doc>
    
    
    <xd:doc>
        <xd:desc>Include the generated configuration file. See
            <xd:a href="create_config_xsl.xsl">create_config_xsl.xsl</xd:a> for
            full documentation of how the configuration file is created.</xd:desc>
    </xd:doc>
    <xsl:include href="config.xsl"/>
    
    <xsl:output  method="json" _indent="{$indentJSON}"/>
    
    <xsl:template match="/">
        <xsl:call-template name="createFiltersJson"/>
        <xsl:call-template name="createStopwordsJson"/>
        <xsl:call-template name="createTitleJson"/>
        <xsl:call-template name="createConfigJson"/>
    </xsl:template>
    
    
    
    <!--**************************************************************
       *                                                            *
       *                      createFiltersJson                     *
       *                                                            *
       **************************************************************-->
    
    <xd:doc>
        <xd:desc>createFiltersJson is a named template that creates files for each filter JSON; it will eventually supercede createDocsJson.
        There are (currently) three types of filters that this process creates:
        
        <xd:ol>
            <xd:li>Desc filters: These are organized as a desc (i.e. Genre) with an array of values (i.e. Poem) that contains an array of document ids that apply to that value (i.e. MyPoem1.html, MyPoem2.html)</xd:li>
            <xd:li>Boolean Filters: These are organized as a desc value (i.e. Discusses Foreign Affairs) with an array of two values: True and False.</xd:li>
            <xd:li>Date filters: These are a bit different than the above. Since dates can contain a range, these JSONs must be organized not by date but by document.</xd:li>
        </xd:ol>
        </xd:desc>
    </xd:doc>
    <xsl:template name="createFiltersJson">
        <!--Filter regex-->
        <xsl:variable name="filterRex"
            select="'(^|\s+)staticSearch_(desc|num|bool|date|feat)(\s+|$)'"
            as="xs:string"/>
        
      <xsl:variable name="ssMetas" 
        select="$filterDocs//meta[matches(@class,$filterRex)][not(ancestor-or-self::*[@ss-excld])]"
        as="element(meta)*"/>
      
        
        <xsl:for-each-group select="$ssMetas" group-by="tokenize(@class,'\s+')[matches(.,$filterRex)]">
            <!--Get the class for the filter (staticSearch_desc, staticSearch_num, etc)-->
            <xsl:variable name="thisFilterClass" 
                select="current-grouping-key()"
                as="xs:string"/>
            
            <!--Stash the group of metas for this filter type-->
            <xsl:variable name="currentMetas"
                select="current-group()"
                as="element(meta)*"/>
            
            <!--Get the base type for the filter (desc, num, etc)-->
            <xsl:variable name="thisFilterType"
                select="replace($thisFilterClass, $filterRex, '$2')"
                as="xs:string"/>
            
            <!--Now create the filter type id (ssDesc, ssNum, etc)-->
            <xsl:variable name="thisFilterTypeId"
                select="'ss' || upper-case(substring($thisFilterType, 1,1)) || substring($thisFilterType, 2)"
                as="xs:string"/>
            
            <!--Now group the current metas by their name-->
            <xsl:for-each-group select="$currentMetas" group-by="normalize-space(@name)">
                
                <!--Get all of the current named filters-->
                <xsl:variable name="thisFilterMetas" 
                    select="current-group()"
                    as="element(meta)*"/>
                
                <!--Get the current name for this filter-->
                <xsl:variable name="thisFilterName" 
                    select="current-grouping-key()"
                    as="xs:string"/>
                
                <!--Get the filter position (which is arbitrary) since we do the sorting below -->
                <xsl:variable name="thisFilterPos" 
                    select="position()" 
                    as="xs:integer"/>
                
                <!--Construct the filter id-->
                <xsl:variable name="thisFilterId"
                    select="$thisFilterTypeId || $thisFilterPos"
                    as="xs:string"/>
   
                <!--Now output the JSON-->
                <xsl:result-document href="{$outDir || '/filters/' || $thisFilterId || $versionString || '.json'}">
                    <xsl:message><xsl:value-of select="current-output-uri()"/></xsl:message>
                    <xsl:map>
                        <xsl:map-entry key="'filterId'" select="string($thisFilterId)"/>
                        <xsl:map-entry key="'filterName'" select="string($thisFilterName)"/>
                        
                        <!--Now fork on filter types and call the respective functions-->
                        <xsl:choose>
                            <xsl:when test="$thisFilterType = ('desc', 'feat')">
                                <xsl:sequence select="hcmc:createDescFeatFilterMap($thisFilterMetas, $thisFilterId)"/>
                            </xsl:when>
                            <xsl:when test="$thisFilterType = 'date'">
                                <xsl:sequence select="hcmc:createDateFilterMap($thisFilterMetas, $thisFilterId)"/>
                            </xsl:when>
                            <xsl:when test="$thisFilterType = 'num'">
                                <xsl:sequence select="hcmc:createNumFilterMap($thisFilterMetas, $thisFilterId)"/>
                            </xsl:when>
                            <xsl:when test="$thisFilterType = 'bool'">
                                <xsl:sequence select="hcmc:createBoolFilterMap($thisFilterMetas, $thisFilterId)"/>
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:message>WARNING: Unknown filter type: <xsl:value-of select="$thisFilterType"/></xsl:message>
                            </xsl:otherwise>
                        </xsl:choose>
                        
                    </xsl:map>
                   
                </xsl:result-document>
                
            </xsl:for-each-group>
        </xsl:for-each-group>
    </xsl:template>
    <xd:doc>
        <xd:desc><xd:ref name="hcmc:createDescFeatFilterMap" type="function">hcmc:createDescFeatFilterMap</xd:ref>
            creates the content for each ssDesc or ssFeature filter map by associating each unique ssDesc|ssFeature value with the
            set of documents to which it corresponds.</xd:desc>
        <xd:param name="metas">All of the meta tags for a particular ssDesc or ssFeature filter (i.e. meta name="Document Type")</xd:param>
        <xd:param name="filterIdPrefix">The id for that filter (ssDesc1 or ssFeature1)</xd:param>
        <xd:return>A sequence of maps for each value:
            ssDesc1_1: {
            name: 'Poem',
            sortKey: 'Poem',
            docs: ['doc1', 'doc2', 'doc10']
            },
            ssDesc1_2: {
            name: 'Novel',
            sortKey: 'Novel',
            docs: ['doc3', 'doc4']
            }
        </xd:return>
    </xd:doc>
    <xsl:function name="hcmc:createDescFeatFilterMap" as="map(*)*">
        <xsl:param name="metas" as="element(meta)+"/>
        <xsl:param name="filterIdPrefix" as="xs:string"/>
        <xsl:map>
            <xsl:for-each-group select="$metas" group-by="xs:string(@content)">
                <xsl:variable name="thisName"
                    select="current-grouping-key()"
                    as="xs:string"/>
                <xsl:variable name="thisPosition"
                    select="position()"
                    as="xs:integer"/>
                <xsl:variable name="filterId" 
                    select="$filterIdPrefix || '_' || $thisPosition" 
                    as="xs:string"/>
                <xsl:variable name="declaredSortKey"
                    select="current-group()[@data-ssFilterSortKey][1]/@data-ssFilterSortKey"
                    as="xs:string?"/>
                <xsl:variable name="currMetas" select="current-group()" as="element(meta)+"/>
                <xsl:variable name="docsArray" select="hcmc:getDocsArrayFromMetas($currMetas)" as="array(xs:string)"/>
                
                <xsl:map-entry key="$filterId">
                    <xsl:map>
                        <xsl:map-entry key="'name'" select="string($thisName)"/>
                        <xsl:map-entry key="'sortKey'" select="if (exists($declaredSortKey)) then $declaredSortKey else $thisName"/>
                        <xsl:map-entry key="'docs'" select="$docsArray"/>
                    </xsl:map>
                </xsl:map-entry>
            </xsl:for-each-group>
        </xsl:map>
    </xsl:function>
    
    <xd:doc>
        <xd:desc><xd:ref name="hcmc:createBoolFilterMap" type="function">hcmc:createBoolFilterMap</xd:ref>
            creates the content for each ssBool filter map by associating each unique ssBool value with the
            set of documents to which it corresponds.</xd:desc>
        <xd:param name="metas">All of the meta tags for a particular ssBool filter (i.e. meta name="Discusses animals?")</xd:param>
        <xd:param name="filterIdPrefix">The id for that filter (ssBool1)</xd:param>
        <xd:return>A sequence of maps for each value:
            ssBool1_1: {
            value: 'true',
            docs: ['doc1','doc2']
            }
            ssBool1_2: {
            value: 'false',
            docs: ['doc3']
            }
        </xd:return>
    </xd:doc>
    <xsl:function name="hcmc:createBoolFilterMap" as="map(*)">
        <xsl:param name="metas" as="element(meta)+"/>
        <xsl:param name="filterIdPrefix" as="xs:string"/>
      <xsl:map>
          <xsl:for-each-group select="$metas" group-by="hcmc:normalize-boolean(@content)">
              
              <!--We have to sort these descending so that we reliably get true followed by false. -->
              <xsl:sort select="current-grouping-key()" order="descending"/>
              
              <xsl:variable name="thisValue"
                  select="current-grouping-key()"
                  as="xs:string"/>
              <xsl:variable name="thisPosition"
                  select="position()"
                  as="xs:integer"/>
              <xsl:variable name="filterId" 
                  select="$filterIdPrefix || '_' || $thisPosition" 
                  as="xs:string"/>
              <xsl:variable name="currMetas" 
                  select="current-group()"
                  as="element(meta)+"/>
              
              <!--If there under two categories, and we're grouping, then we have a lopsided boolean-->
              <xsl:if test="last() lt 2">
                  <xsl:message><xsl:value-of select="$filterId"/> only contains <xsl:value-of select="$thisValue"/>.</xsl:message>
              </xsl:if>
              <xsl:variable name="docsArray" select="hcmc:getDocsArrayFromMetas($currMetas)" as="array(xs:string)"/>
              
              <xsl:map-entry key="$filterId">
                  <xsl:map>
                      <xsl:map-entry key="'value'" select="$thisValue"/>
                      <xsl:map-entry key="'docs'" select="$docsArray"/>
                  </xsl:map>
              </xsl:map-entry>
          </xsl:for-each-group>
      </xsl:map>
        
    </xsl:function>
    
    <xd:doc>
        <xd:desc><xd:ref name="hcmc:createDateFilterMap" type="function">hcmc:createDateFilterMap</xd:ref>
            creates the content for each ssDate filter map.</xd:desc>
        <xd:param name="metas">All of the meta tags for a particular ssDate filter (i.e. meta name="Date of Publication")</xd:param>
        <xd:param name="filterIdPrefix">The id for that filter (ssDate1)</xd:param>
        <xd:return>A map organized by document:
            {
            doc1: ['1922'],
            doc2: ['1923','1924'] //Represents a range
            }
        </xd:return>
    </xd:doc>
    <xsl:function name="hcmc:createDateFilterMap" as="map(*)">
        <xsl:param name="metas" as="element(meta)+"/>
        <xsl:param name="filterIdPrefix" as="xs:string"/>
        
        <xsl:map>
            <xsl:map-entry key="'docs'">
                <xsl:map>
                    <xsl:for-each-group select="$metas" group-by="string(ancestor::html/@data-staticSearch-relativeUri)">
                        <xsl:variable name="docUri" select="current-grouping-key()" as="xs:string"/>
                        <xsl:variable name="metasForDoc" select="current-group()" as="element(meta)+"/>
                        <xsl:variable name="dates" as="xs:string+">
                            <xsl:for-each select="$metasForDoc">
                                <!--Split the date on slashes, which represent a range of dates-->
                                <!--TODO: Verify that there are proper dates here-->
                                <xsl:for-each select="tokenize(@content,'/')">
                                    <xsl:sequence select="."/>
                                </xsl:for-each>
                            </xsl:for-each>
                        </xsl:variable>
                        <xsl:map-entry key="$docUri" select="array{$dates}"/>
                    </xsl:for-each-group>
                </xsl:map>
            </xsl:map-entry>
        </xsl:map>
    </xsl:function>
    
    <xd:doc>
        <xd:desc><xd:ref name="hcmc:createNumFilterMap" type="function">hcmc:createNumFilterMap</xd:ref>
            creates the content for each ssNum filter map by creating a single map, which associates each document
            with an array of values that it satisfies.</xd:desc>
        <xd:param name="metas">All of the meta tags for a particular ssNum filter (i.e. meta name="Word count")</xd:param>
        <xd:param name="filterIdPrefix">The id for that filter (ssNum1)</xd:param>
        <xd:return>A map organized by document:
            {
            doc1: ['130'],
            doc2: ['2490']
            }
        </xd:return>
    </xd:doc>
    <xsl:function name="hcmc:createNumFilterMap" as="map(*)">
        <xsl:param name="metas" as="element(meta)+"/>
        <xsl:param name="filterIdPrefix" as="xs:string"/>
        <xsl:map>
            <xsl:map-entry key="'docs'">
                <xsl:map>
                    <xsl:for-each-group select="$metas" group-by="string(ancestor::html/@data-staticSearch-relativeUri)">
                        <xsl:variable name="docUri" select="current-grouping-key()" as="xs:string"/>
                        <xsl:variable name="metasForDoc" select="current-group()" as="element(meta)+"/>
                        <!--NOTE THAT THESE ARE STRINGS-->
                        <xsl:variable name="nums" as="xs:string*">
                            <xsl:for-each-group select="current-group()[@content castable as xs:decimal]" group-by="xs:decimal(@content)">
                                <xsl:sequence select="xs:decimal(current-grouping-key()) => xs:string()"/>
                            </xsl:for-each-group>
                        </xsl:variable>
                        <xsl:map-entry key="$docUri" select="array{$nums}"/>
                    </xsl:for-each-group>
                </xsl:map>
            </xsl:map-entry>
        </xsl:map>
    </xsl:function>
    
    <xd:doc>
        <xd:desc><xd:ref name="hcmc:getDocsArrayFromMetas" type="function">hcmc:getDocsArrayFromMetas</xd:ref>
            takes all of the metas for a filter, compiles the distinct document URIs, and
            returns those as an array of strings.</xd:desc>
        <xd:param name="currMetas">The current set of metas for a filter.</xd:param>
        <xd:return>An array of document URIs as strings.</xd:return>
    </xd:doc>
    <xsl:function name="hcmc:getDocsArrayFromMetas" as="array(xs:string)">
        <xsl:param name="currMetas" as="element(meta)*"/>
        <xsl:sequence select="array{distinct-values(for $meta in $currMetas return string(root($meta)/html/@data-staticSearch-relativeUri))}"/>
    </xsl:function>
    
    
    <!--**************************************************************
       *                                                            *
       *                    createStopwordsJson                     *
       *                                                            *
       **************************************************************-->
    
    <xd:doc>
        <xd:desc><xd:ref name="createStopwordsJson">createStopwordsJson</xd:ref>
        builds a JSON file containing the list of stopwords (either the default list or the 
        one provided by the project and referenced in its config file).</xd:desc>
    </xd:doc>
    <xsl:template name="createStopwordsJson">
        <xsl:message>Creating stopwords array...</xsl:message>
        <xsl:result-document href="{$outDir}/ssStopwords{$versionString}.json">
            <xsl:apply-templates select="$stopwordsFileXml" mode="dictToArray"/>
        </xsl:result-document>
    </xsl:template>
    
    
    
    <!--**************************************************************
       *                                                            *
       *                        createTitleJson                     *
       *                                                            *
       **************************************************************-->
    
    <xd:doc>
        <xd:desc><xd:ref name="createTitleJson">createTitleJson</xd:ref>
            builds a JSON file containing a list of all the titles of documents in the 
        collection, indexed by their relative URI (which serves as their identifier),
        to be used when displaying results in the search page.</xd:desc>
    </xd:doc>
    <xsl:template name="createTitleJson">
        <xsl:result-document href="{$outDir}/ssTitles{$versionString}.json">
            <xsl:map>
                <xsl:for-each select="$filterDocs//html">
                    <xsl:map>
                        <xsl:map-entry 
                            key="@data-staticSearch-relativeUri" 
                            select="array{hcmc:getDocTitle(.), hcmc:getDocThumbnail(.), hcmc:getDocSortKey(.)}"/>
                    </xsl:map>
                </xsl:for-each>
            </xsl:map>
        </xsl:result-document>
    </xsl:template>
    
  


    <!--**************************************************************
       *                                                            *
       *                       createConfigJson                     *
       *                                                            *
       **************************************************************-->
    
    <xd:doc>
        <xd:desc><xd:ref name="createConfigJson">createConfigJson</xd:ref> 
            creates a JSON representation of the project's configuration file.
        This is not currently used for any specific purpose, but it may be 
        helpful for the JS search engine to know what configuration was 
        used to create the indexes at some point.</xd:desc>
        <xd:return>The configuration file in JSON.</xd:return>
    </xd:doc>
    <xsl:template name="createConfigJson">
        <xsl:message>Creating Configuration JSON file....</xsl:message>
        <xsl:result-document href="{$outDir}/config{$versionString}.json">
            <xsl:apply-templates select="doc($configFile)" mode="configToArray"/>
        </xsl:result-document>
    </xsl:template>
    
    

    <!--**************************************************************
       *                                                            *
       *                     templates: dictToArray                 *
       *                                                            *
       **************************************************************-->
    
    <xd:doc>
        <xd:desc>Template to convert an XML structure consisting
        of word elements inside a words element to a JSON/XML structure.</xd:desc>
    </xd:doc>
    <xsl:template match="hcmc:words" mode="dictToArray">
        <xsl:variable name="words" as="xs:string*">
            <xsl:apply-templates mode="#current"/>
        </xsl:variable>
        <xsl:map>
            <xsl:map-entry key="'words'" select="array{$words}"/>
        </xsl:map>
    </xsl:template>

    <xd:doc>
        <xd:desc>Template to convert a single word element inside 
            a words element to a JSON/XML string.</xd:desc>
    </xd:doc>
    <xsl:template match="hcmc:word" mode="dictToArray">
        <xsl:sequence select="string(.)"/>
    </xsl:template>
    

    <!--**************************************************************
       *                                                            *
       *                     templates: configToArray               *
       *                                                            *
       **************************************************************-->
    
    <xd:doc>
        <xd:desc>Template to convert an hcmc:config element to a JSON map.</xd:desc>
    </xd:doc>
    <xsl:template match="hcmc:config" mode="configToArray">
        <xsl:map>
            <xsl:map-entry key="'config'">
                <xsl:map>
                    <xsl:apply-templates select="hcmc:params" mode="#current"/>
                </xsl:map>

            </xsl:map-entry>
        </xsl:map>
    </xsl:template>

    <xd:doc>
        <xd:desc>Template to convert an hcmc:params element to a JSON array.</xd:desc>
    </xd:doc>
    <xsl:template match="hcmc:params" mode="configToArray">
        <xsl:variable name="result" as="map(*)*">
            <xsl:apply-templates select="hcmc:*" mode="#current"/>
        </xsl:variable>
        <xsl:map-entry key="'params'" select="array{$result}"/>
    </xsl:template>

    <xd:doc>
        <xd:desc>Template to convert any child of an hcmc:params element to a JSON value.</xd:desc>
    </xd:doc>
    <xsl:template match="hcmc:params/hcmc:*" mode="configToArray">
        <xsl:map>
            <xsl:map-entry key="local-name()" select="if (text() castable as xs:integer) then xs:integer(text()) else xs:string(text())"/>
        </xsl:map>
    </xsl:template>
    
    
    
    
    <xd:doc>
        <xd:desc><xd:ref name="hcmc:normalize-boolean">hcmc:normalize-boolean</xd:ref>
            takes any of a variety of different boolean representations and converts them to
            string "true" or string "false".</xd:desc>
        <xd:param name="string">The input string.</xd:param>
        <xd:return>A string value that represents the boolean true/false.</xd:return>
    </xd:doc>
    <xsl:function name="hcmc:normalize-boolean" as="xs:string">
        <xsl:param name="string" as="xs:string"/>
        <xsl:value-of select="if (matches(normalize-space($string),'true|1','i')) then 'true' else 'false'"/>
    </xsl:function>


    <xd:doc>
        <xd:desc><xd:ref name="hcmc:getDocTitle" type="function">hcmc:getDocTitle</xd:ref> is a simple function to retrieve 
                the document title, which we may have to construct if there's nothing usable.</xd:desc>
        <xd:param name="doc">The input document, which must be an HTML element.</xd:param>
        <xd:result>A string title, derived from the document's actual title, a configured document title,
            or the document's @id if all else fails.</xd:result>
    </xd:doc>
    <xsl:function name="hcmc:getDocTitle" as="xs:string">
        <xsl:param name="doc" as="element(html)"/>
        <xsl:variable name="defaultTitle" select="normalize-space(string-join($doc//head/title[1]/descendant::text(),''))" as="xs:string?"/>
        <xsl:variable name="docTitle" 
            select="$doc/head/meta[@name='docTitle'][contains-token(@class,'staticSearch_docTitle')][not(@ss-excld)]"
            as="element(meta)*"/>
        <xsl:choose>
            <xsl:when test="exists($docTitle)">
                <xsl:if test="count($docTitle) gt 1">
                    <xsl:message>WARNING: Multiple docTitles declared in <xsl:value-of select="$doc/@data-staticSearch-relativeUri"/>. Using <xsl:value-of select="$docTitle[1]/@content"/></xsl:message>
                </xsl:if>
                <xsl:value-of select="normalize-space($docTitle[1]/@content)"/>
            </xsl:when>
            <xsl:when test="string-length($defaultTitle) gt 0">
                <xsl:value-of select="$defaultTitle"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:value-of select="$doc/@id"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>
    
    
    <xd:doc>
        <xd:desc><xd:ref name="hcmc:getDocThumbnail" type="function">hcmc:getDocThumbnail</xd:ref> 
                generates a j:string element containing a pointer to the first of any configured graphics, 
                relative to the search page location. NOTE: this function assumes that the graphic path has
            been massaged as necessary during the tokenizing process, so that it is now relative to the 
            search page location, not to the containing document.</xd:desc>
        <xd:param name="doc">The input document, which must be an HTML element.</xd:param>
        <xd:result>A j:string element, if there is a configured graphic, or an empty string if there is a subsequent sort key, or the empty
            sequence if not. We return the empty string in the 
        second case so that the sort key ends up at the right 
        position in the array.</xd:result>
    </xd:doc>
    <xsl:function name="hcmc:getDocThumbnail" as="xs:string?">
        <xsl:param name="doc" as="element(html)"/>
        <xsl:variable name="docImage" select="$doc/head/meta[@name='docImage'][contains-token(@class,'staticSearch_docImage')][not(@ss-excld)]" 
            as="element(meta)*"/>
        <xsl:variable name="docSortKey" 
            select="$doc/head/meta[@name='docSortKey'][contains-token(@class,'staticSearch_docSortKey')][not(@ss-excld)]" 
            as="element(meta)*"/>
        <xsl:choose>
            <xsl:when test="exists($docImage)">
                <xsl:if test="count($docImage) gt 1">
                    <xsl:message>WARNING: Multiple docImages declared in <xsl:value-of select="$doc/@data-staticSearch-relativeUri"/>. Using <xsl:value-of select="$docImage[1]/@content"/></xsl:message>
                </xsl:if>
                <xsl:sequence select="xs:string($docImage[1]/@content)"/>
             
            </xsl:when>
            <xsl:when test="exists($docSortKey)">
                <xsl:sequence select="''"/>
            </xsl:when>
        </xsl:choose>
    </xsl:function>
    
    <xd:doc>
        <xd:desc><xd:ref name="hcmc:getDocSortKey" type="function">hcmc:getDocSortKey</xd:ref> 
            generates a j:string element containing a string read
            from the meta[@name='ssDocSortKey'] element if there
            is one, or the empty sequence if not.</xd:desc>
        <xd:param name="doc">The input document, which must be an HTML element.</xd:param>
        <xd:result>A j:string element, if there is a configured sort key, or the empty sequence.</xd:result>
    </xd:doc>
    <xsl:function name="hcmc:getDocSortKey" as="xs:string?">
        <xsl:param name="doc" as="element(html)"/>
        <xsl:variable name="docSortKey" 
            select="$doc/head/meta[@name='docSortKey'][contains-token(@class,'staticSearch_docSortKey')][not(@ss-excld)]" 
            as="element(meta)*"/>
        <xsl:if test="exists($docSortKey)">
            <xsl:if test="count($docSortKey) gt 1">
                <xsl:message>WARNING: Multiple docSortKeys declared in <xsl:value-of select="$doc/@data-staticSearch-relativeUri"/>. Using <xsl:value-of select="$docSortKey[1]/@content"/></xsl:message>
            </xsl:if>
            <xsl:sequence select="string($docSortKey[1]/@content)"/>
        </xsl:if>
    </xsl:function>
    
    
</xsl:stylesheet>